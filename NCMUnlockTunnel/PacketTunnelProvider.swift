import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var proxy: ProxyServer?
    private let proxyPort = 8899

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // 给隧道一个私网地址
        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = NSNumber(value: 1500)

        // 关键：把本机设为 HTTP/HTTPS 代理，所有 App 流量走我们的 MITM 代理
        let proxySettings = NEProxySettings()
        let sv = "127.0.0.1"
        let p = "\(proxyPort)"
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: sv, port: proxyPort)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: sv, port: proxyPort)
        // 排除本机回环，避免代理自身流量回环
        proxySettings.exceptionList = ["127.0.0.1", "localhost"]
        // 只让网易云等目标走代理（其余直连，减少干扰）
        proxySettings.matchDomains = [""] // 空串 = 匹配所有域名
        settings.proxySettings = proxySettings

        // 不接管真实 IP 层的路由，仅用代理模式
        settings.tunnelOverheadBytes = 0

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return completionHandler(error) }
            if let error = error {
                NSLog("[ncm] setTunnelNetworkSettings error: \(error)")
                return completionHandler(error)
            }
            do {
                let server = ProxyServer(port: self.proxyPort)
                try server.start()
                self.proxy = server
                NSLog("[ncm] tunnel started, proxy on :\(self.proxyPort)")
                completionHandler(nil)
            } catch {
                NSLog("[ncm] proxy start failed: \(error)")
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        proxy?.stop()
        proxy = nil
        completionHandler()
    }
}
