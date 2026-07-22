import Foundation
import NIO
import NIOSSL

/// 本地 MITM 代理（跑在 NetworkExtension 内，127.0.0.1:port）。
/// 流程：
///   1. 客户端发 `CONNECT host:port`；
///   2. 网易云主机 -> 返回 200 后做 TLS MITM（用我们的 CA 签发的叶子证书）；
///      其它主机 -> 返回 200 后做纯 TCP 透传；
///   3. 解密后的 HTTPS 请求里，命中风控接口的 POST 走「转发到真实服务器 +
///      eapi 解锁 + 回包」；其余透明转发。
final class ProxyServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    let port: Int
    private var channel: Channel?
    private let ca = CertAuthority.shared

    init(port: Int) { self.port = port }

    func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self = self else { return channel.eventLoop.makeSucceededFuture(()) }
                return channel.pipeline.addHandler(ProxyHandler(ca: self.ca))
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 8)

        channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        NSLog("[ncm] proxy listening on 127.0.0.1:\(port)")
    }

    func stop() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
    }
}

/// 透传用的转发处理器：把读到的字节写进 peer channel。
final class ForwardHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    weak var peer: Channel?
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let peer = peer else { return }
        var buf = unwrapInboundIn(data)
        peer.writeAndFlush(NIOAny(buf), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        try? peer?.close().flatMap { _ in context.close() }.wait()
    }
}

final class ProxyHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum Phase { case plain, mitm, tunnel }
    var phase: Phase = .plain
    var buffer = ByteBufferAllocator().buffer(capacity: 8192)
    let ca: CertAuthority

    /// 透传模式下的上游通道
    var upstream: Channel?
    /// 当前 CONNECT 的目标主机（MITM 时需要叶子证书 SAN）
    var connectHost: String = ""

    init(ca: CertAuthority) { self.ca = ca }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        buffer.writeBuffer(&buf)

        switch phase {
        case .plain:
            tryReadConnect(context: context)
        case .mitm:
            tryReadHTTP(context: context)
        case .tunnel:
            // 把客户端后续字节直接写给上游
            if let up = upstream {
                var b = buf
                up.writeAndFlush(NIOAny(b), promise: nil)
            }
        }
    }

    // MARK: - 阶段 1：解析 CONNECT

    private func indexOfCRLFCRLF() -> Int? {
        let view = buffer.readableBytesView
        guard view.count >= 4 else { return nil }
        for i in 0..<(view.count - 3) {
            if view[i] == 13 && view[i+1] == 10 && view[i+2] == 13 && view[i+3] == 10 {
                return i
            }
        }
        return nil
    }

    private func tryReadConnect(context: ChannelHandlerContext) {
        guard let end = indexOfCRLFCRLF() else { return } // 头还没收全
        let headerLen = end + 4
        guard let headerData = buffer.readSlice(length: headerLen)?.withUnsafeReadableBytes({ Data($0) }),
              let text = String(data: headerData, encoding: .ascii) else { return }

        let firstLine = text.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else {
            // 非 CONNECT（理论上不会发生，因为我们是显式代理入口）
            respond(context: context, "HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            return
        }
        let target = parts[1]
        let comps = target.components(separatedBy: ":")
        connectHost = comps.first ?? target
        let port = Int(comps.dropFirst().first ?? "443") ?? 443

        if isNeteaseHost(connectHost) {
            beginMITM(context: context, host: connectHost)
        } else {
            beginTunnel(context: context, host: connectHost, port: port)
        }
    }

    private func respond(context: ChannelHandlerContext, _ s: String) {
        var buf = context.channel.allocator.buffer(capacity: s.utf8.count)
        buf.writeString(s)
        context.writeAndFlush(NIOAny(buf), promise: nil)
    }

    // MARK: - 阶段 2a：网易云 -> TLS MITM

    private func beginMITM(context: ChannelHandlerContext, host: String) {
        respond(context: context, "HTTP/1.1 200 Connection Established\r\n\r\n")

        guard let (cert, key) = ca.leaf(for: host) else {
            NSLog("[ncm] leaf cert failed for \(host)")
            try? context.close().wait()
            return
        }
        let tlsConf: TLSConfiguration
        do {
            tlsConf = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
        } catch {
            NSLog("[ncm] TLS config failed: \(error)")
            try? context.close().wait()
            return
        }

        let addFuture: EventLoopFuture<Void>
        do {
            let sslServer = try NIOSSLServerHandler(context: NIOSSLContext(configuration: tlsConf))
            // 放在管道最前面：入站先经它解密，再交给 ProxyHandler
            addFuture = context.pipeline.addHandler(sslServer, position: .first)
        } catch {
            NSLog("[ncm] NIOSSLServerHandler failed: \(error)")
            try? context.close().wait()
            return
        }

        addFuture.whenSuccess { [weak self] in
            self?.phase = .mitm
            // 若 CONNECT 段里已夹带 ClientHello，重新喂入管道让其被解密
            if let self = self, self.buffer.readableBytes > 0 {
                let left = self.buffer
                self.buffer = ByteBufferAllocator().buffer(capacity: 8192)
                context.pipeline.fireChannelRead(NIOAny(left))
            }
        }
        addFuture.whenFailure { err in
            NSLog("[ncm] add ssl server failed: \(err)")
            try? context.close().wait()
        }
    }

    // MARK: - 阶段 2b：其它主机 -> 纯 TCP 透传

    private func beginTunnel(context: ChannelHandlerContext, host: String, port: Int) {
        respond(context: context, "HTTP/1.1 200 Connection Established\r\n\r\n")
        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelInitializer { ch in
                let fwd = ForwardHandler()
                fwd.peer = context.channel
                return ch.pipeline.addHandler(fwd)
            }
        let conn = bootstrap.connect(host: host, port: port)
        conn.whenSuccess { [weak self] up in
            guard let self = self else { return }
            self.upstream = up
            self.phase = .tunnel
            // 把 CONNECT 之后可能夹带的早期数据写给上游
            if self.buffer.readableBytes > 0 {
                var b = self.buffer
                self.buffer = ByteBufferAllocator().buffer(capacity: 8192)
                up.writeAndFlush(NIOAny(b), promise: nil)
            }
            // 上游回包 -> 写回客户端
            _ = up.closeFuture.map { _ in try? context.close().wait() }
        }
        conn.whenFailure { err in
            NSLog("[ncm] tunnel connect failed: \(err)")
            try? context.close().wait()
        }
    }

    // MARK: - 阶段 3：MITM 下解析 HTTPS 请求并改写

    private func tryReadHTTP(context: ChannelHandlerContext) {
        // 至少需要请求头
        guard let end = indexOfCRLFCRLF() else { return }
        let headerLen = end + 4
        guard let headerData = buffer.readSlice(length: headerLen)?.withUnsafeReadableBytes({ Data($0) }),
              let text = String(data: headerData, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\r\n")
        let reqLine = lines.first?.components(separatedBy: " ")
        guard let method = reqLine?.first, let path = reqLine?.dropFirst().first else { return }

        var headers: [String: String] = [:]
        for l in lines.dropFirst() where !l.isEmpty {
            let kv = l.components(separatedBy: ": ")
            if kv.count == 2 { headers[kv[0].lowercased()] = kv[1] }
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0

        // 等 body 收全
        guard buffer.readableBytes >= contentLength else { return }

        let body = buffer.readSlice(length: contentLength)?.withUnsafeReadableBytes({ Data($0) }) ?? Data()

        // 还原目标 URL（CONNECT 阶段已拿到 connectHost）
        let url = "https://\(connectHost)\(path)"
        handleRequest(context: context, method: method, url: url, headers: headers, body: body)
    }

    private func handleRequest(context: ChannelHandlerContext, method: String,
                               url: String, headers: [String: String], body: Data) {
        // 仅对命中解锁接口的 POST 做改写；其余透明转发
        let shouldUnlock = method.uppercased() == "POST"
            && isUnlockPath(url)
            && isNeteaseHost(connectHost)

        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseHeaders: [String: String] = [:]
        var statusCode = 200

        let session = URLSession(configuration: .ephemeral)
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 12)
        req.httpMethod = method.uppercased()
        for (k, v) in headers where k.lowercased() != "proxy-connection"
                                   && k.lowercased() != "connection" {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = shouldUnlock ? rewriteRequestBody(body) : body

        let task = session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            guard let data = data, err == nil else { statusCode = 502; return }
            if let http = resp as? HTTPURLResponse { statusCode = http.statusCode }
            if shouldUnlock {
                let (json, encrypted) = EapiCrypto.unwrapBody(data)
                let unlocked = EAPIHandler.unlock(json)
                responseData = EapiCrypto.wrapBody(json: unlocked, encrypted: encrypted)
                responseHeaders["Content-Type"] = "application/json"
                NSLog("[ncm][ok] \(url) -> unlocked")
            } else {
                responseData = data
            }
        }
        task.resume()
        sem.wait()

        // 回包给客户端（经 NIOSSLServerHandler 加密）
        var out = context.channel.allocator.buffer(capacity: 256)
        out.writeString("HTTP/1.1 \(statusCode) OK\r\n")
        out.writeString("Connection: close\r\n")
        if let data = responseData {
            out.writeString("Content-Length: \(data.count)\r\n")
        }
        for (k, v) in responseHeaders { out.writeString("\(k): \(v)\r\n") }
        out.writeString("\r\n")
        if let data = responseData {
            var b = context.channel.allocator.buffer(capacity: data.count)
            b.writeBytes(data)
            out.writeBuffer(&b)
        }
        context.writeAndFlush(NIOAny(out), promise: nil)
        try? context.close().wait()
    }

    /// 把请求体里携带的试听/受限标记一并清掉（与响应改写互补）
    private func rewriteRequestBody(_ body: Data) -> Data {
        let (json, encrypted) = EapiCrypto.unwrapBody(body)
        guard !json.isEmpty else { return body }
        var root: [String: Any]? = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any])
        root?["e_r"] = "0"           // 去掉「试听」标记
        root?["freeTime"] = "0"
        guard let out = try? JSONSerialization.data(withJSONObject: root as Any) else { return body }
        return EapiCrypto.wrapBody(json: String(data: out, encoding: .utf8) ?? json, encrypted: encrypted)
    }
}
