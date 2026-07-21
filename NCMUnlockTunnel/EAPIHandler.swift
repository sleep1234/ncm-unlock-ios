import Foundation

/// 对解密后的 eapi 响应 JSON 做 VIP 解锁。
/// 逻辑移植自安卓 ncm-unlock 模块的 EAPIHook.modifyPlayer / modifySingleSongPrivilege：
/// 清除 fee/flag/freeTrialInfo 等限制字段，对 VIP/试听/无 URL 的歌曲向 GD Studio 取完整播放地址替换。
enum EAPIHandler {

    /// 输入：解密后的明文 JSON 字符串；输出：改写后的明文 JSON 字符串。
    /// 非 JSON / 解析失败则原样返回。
    static func unlock(_ jsonText: String) -> String {
        guard let data = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return jsonText
        }
        var root = obj
        if var arr = root["data"] as? [[String: Any]] {
            for i in 0..<arr.count { arr[i] = processOne(arr[i]) }
            root["data"] = arr
        }
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return jsonText
        }
        return String(data: out, encoding: .utf8) ?? jsonText
    }

    /// 单首歌处理
    private static func processOne(_ song: [String: Any]) -> [String: Any] {
        var s = song
        let fee = s["fee"] as? Int ?? 0
        let flag = s["flag"] as? Int ?? 0
        let trial = s["freeTrialInfo"] as? [String: Any]
        let id = s["id"] as? Int ?? 0
        let hasUrl = (s["url"] as? String)?.isEmpty == false

        // 清除所有限制标记（使其看起来像已购/可播）
        s["fee"] = 0
        s["flag"] = 0
        s["payed"] = 1
        s["vipType"] = 0
        s["freeTrialInfo"] = nil
        s["freeTrialPrivileges"] = nil

        // VIP / 试听 / 无有效 URL -> 向 GD Studio 换源
        if (fee != 0 || flag != 0 || trial != nil || !hasUrl), id != 0 {
            if let r = GDStudio.shared.fetch(songId: id, br: DEFAULT_BR) {
                s["url"] = r.url
                if r.br != 0 { s["br"] = r.br }
                if r.size != 0 { s["size"] = r.size }
                // 置空 md5，规避下载校验（与安卓模块 DownloadMD5Hook 思路一致）
                s["md5"] = ""
            }
        }
        return s
    }
}
