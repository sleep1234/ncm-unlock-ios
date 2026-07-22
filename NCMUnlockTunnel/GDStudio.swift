import Foundation

/// GD Studio 解锁 API 客户端：根据 song id + 码率拿到完整播放地址
final class GDStudio {
    static let shared = GDStudio()

    private let cache = NSCache<NSString, GDResult>()
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutInterval = 8
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0"]
        self.session = URLSession(configuration: cfg)
        cache.countLimit = 2000
    }

    struct GDResult {
        let url: String
        let br: Int
        let size: Int
    }

    /// 返回可用播放地址；失败返回 nil。带缓存与 999 兜底。
    func fetch(songId: Int, br: Int = DEFAULT_BR) -> GDResult? {
        if let cached = cached(songId: songId, br: br) { return cached }
        for tryBr in [br, FALLBACK_BR] where tryBr != br || br == FALLBACK_BR {
            if let r = request(songId: songId, br: tryBr) {
                store(songId: songId, br: tryBr, result: r)
                store(songId: songId, br: FALLBACK_BR, result: r)
                return r
            }
        }
        return nil
    }

    private func request(songId: Int, br: Int) -> GDResult? {
        var comps = URLComponents(string: GD_API_BASE)!
        comps.queryItems = [
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "id", value: String(songId)),
            URLQueryItem(name: "br", value: String(br)),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var out: GDResult?
        let task = session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            guard err == nil, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) else { return }
            let arr = obj as? [[String: Any]] ?? (obj as? [String: Any]).map { [$0] } ?? []
            guard let first = arr.first else { return }
            guard let u = first["url"] as? String, u.hasPrefix("http") else { return }
            let gbr = (first["br"] as? Int) ?? 0
            let gsize = (first["size"] as? Int) ?? 0
            out = GDResult(url: u, br: gbr, size: gsize)
        }
        task.resume()
        sem.wait()
        return out
    }

    private func cached(songId: Int, br: Int) -> GDResult? {
        lock.lock(); defer { lock.unlock() }
        return cache.object(forKey: "\(songId)_\(br)" as NSString)
    }

    private func store(songId: Int, br: Int, result: GDResult) {
        lock.lock(); defer { lock.unlock() }
        cache.setObject(result, forKey: "\(songId)_\(br)" as NSString)
    }
}
