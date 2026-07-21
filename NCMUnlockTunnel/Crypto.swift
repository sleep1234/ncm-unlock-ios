import Foundation
import CommonCrypto

/// 网易云 eapi 信封加解密（AES-128-ECB, key="e82ckenh8dichen8", PKCS7, Hex 大写）
/// 与安卓 NeteaseAES2 行为一致。使用系统 CommonCrypto，零第三方依赖。
enum EapiCrypto {
    private static let keyData = "e82ckenh8dichen8".data(using: .utf8)!

    /// 明文 -> "params=" + Hex(AES-ECB(明文))，返回可直接放进请求/响应体的 Hex 串
    static func encrypt(_ plainText: String) -> String {
        let plain = plainText.data(using: .utf8) ?? Data()
        guard let ct = aesECB(plain, encrypt: true) else { return "" }
        return ct.map { String(format: "%02X", $0) }.joined()
    }

    /// Hex(AES-ECB(密文)) -> 明文
    static func decrypt(_ hexText: String) -> String {
        guard hexText.count % 2 == 0,
              let data = Data(hexString: hexText) else { return "" }
        guard let pt = aesECB(data, encrypt: false) else { return "" }
        return String(data: pt, encoding: .utf8) ?? ""
    }

    /// 解析响应体：以 "params=" 开头视为加密信封
    static func unwrapBody(_ body: Data) -> (json: String, encrypted: Bool) {
        guard let text = String(data: body, encoding: .utf8) else {
            return ("", false)
        }
        if text.hasPrefix("params=") {
            let hex = String(text.dropFirst("params=".count))
            let dec = decrypt(hex)
            return (dec.isEmpty ? text : dec, true)
        }
        return (text, false)
    }

    /// 按原信封格式回包
    static func wrapBody(json: String, encrypted: Bool) -> Data {
        if encrypted {
            return ("params=" + encrypt(json)).data(using: .utf8) ?? Data()
        }
        return json.data(using: .utf8) ?? Data()
    }

    private static func aesECB(_ data: Data, encrypt: Bool) -> Data? {
        guard !data.isEmpty else { return Data() }
        // 加密需要按 16 字节分组并 PKCS7 填充；解密由 CCCrypt 自动去填充
        let padded: Data
        if encrypt {
            padded = data + pkcs7Pad(data)
        } else {
            padded = data
        }
        var out = Data(count: padded.count)
        var outLen = 0
        let status = padded.withUnsafeBytes { inBuf in
            out.withUnsafeMutableBytes { outBuf in
                CCCrypt(encrypt ? kCCEncrypt : kCCDecrypt,
                        kCCAlgorithmAES128,
                        kCCOptionECBMode | kCCOptionPKCS7Padding,
                        (keyData as NSData).bytes, kCCKeySizeAES128,
                        nil,
                        inBuf.baseAddress, padded.count,
                        outBuf.baseAddress, out.count, &outLen)
            }
        }
        guard status == kCCSuccess, outLen > 0 else { return nil }
        return out.prefix(outLen)
    }

    private static func pkcs7Pad(_ data: Data) -> Data {
        let pad = 16 - (data.count % 16)
        return Data(repeating: UInt8(pad), count: pad)
    }
}

extension Data {
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self = Data(bytes)
    }
}
