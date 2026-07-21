import Foundation

/// 网易云相关主机（用于判断是否拦截/MITM）
let NETEASE_HOSTS: Set<String> = [
    "interface3.music.163.com",
    "interface.music.163.com",
    "music.163.com",
    "httpdns.n.netease.com",
    "netservice.kugou.com",
]

/// 需要改写的接口路径关键字（命中则做 VIP 解锁）
let UNLOCK_PATHS: [String] = [
    "player/url",
    "location/info",
    "enhance/privilege",
    "v3/song/detail",
    "song/detail",
]

/// GD Studio 解锁 API 基址
let GD_API_BASE = "https://music-api.gdstudio.xyz/api.php"

/// 本地隧道地址（DNS 把网易云解析到这个 IP，TLS 监听也绑在这里）
let TUN_LOCAL_IP = "10.0.0.1"
let TUN_SUBNET = "10.0.0.0"
let TUN_PREFIX = 30
let TUN_MTU: UInt16 = 1500

/// 默认请求码率 / 兜底无损码率
let DEFAULT_BR = 320
let FALLBACK_BR = 999

/// 判断主机是否属于网易云（支持子域）
func isNeteaseHost(_ host: String) -> Bool {
    let h = host.lowercased()
    if NETEASE_HOSTS.contains(h) { return true }
    return h.hasSuffix(".music.163.com") || h.hasSuffix(".netease.com")
}

/// 判断路径是否需要解锁改写
func isUnlockPath(_ path: String) -> Bool {
    UNLOCK_PATHS.contains(where: { path.contains($0) })
}
