import Foundation
import Security
import NIOSSL

/// 自签名 CA + 叶子证书生成。
///
/// 说明：`SecCertificateCreateCertificate` 已在现代 SDK 中移除，因此这里手动做
/// ASN.1 DER 编码，再用 `SecKeyCreateSignature`(.rsaSignatureMessagePKCS1v15SHA256)
/// 完成 RSA+SHA256 签名。私钥走 `SecKeyGeneratePair`（仍可用），再以 PKCS#8 DER
/// 暴露给 NIOSSL 使用。
final class CertAuthority {
    static let shared = CertAuthority()

    private let lock = NSLock()

    /// CA 证书 DER（供用户安装描述文件 / 共享导出）
    private var caCertDER: Data!
    /// CA 私钥 PKCS#8 DER
    private var caKeyPKCS8: Data!
    /// CA 私钥 SecKey（给叶子证书签名用）
    private var caSecKey: SecKey!

    private init() { buildCA() }

    // MARK: - 对外接口

    /// CA 公钥证书 DER（导出给用户安装，使 App 信任我们的 MITM 证书）
    func exportCACertificate() -> Data { caCertDER }

    /// 为 host 生成一张叶子证书，返回 NIOSSL 所需的证书 + 私钥。
    /// 证书由我们的 CA 签发，SAN 命中该 host，因此 MITM 时客户端不会报域名不匹配。
    func leaf(for host: String) -> (cert: NIOSSLCertificate, key: NIOSSLPrivateKey)? {
        lock.lock(); defer { lock.unlock() }
        guard let kp = generateRSA() else { return nil }
        guard let pubDER = SecKeyCopyExternalRepresentation(kp.public, nil) as Data? else { return nil }
        guard let leafDER = makeCert(subjectCN: host,
                                     issuerCN: "NCM Unlock CA",
                                     issuerKey: caSecKey,
                                     pubKeyDER: pubDER,
                                     san: host,
                                     serial: randomSerial(),
                                     isCA: false) else { return nil }
        guard let pkcs8 = pkcs8(fromPKCS1: SecKeyCopyExternalRepresentation(kp.private, nil) as? Data) else { return nil }
        guard let cert = try? NIOSSLCertificate(bytes: [UInt8](leafDER), format: .der),
              let key = try? NIOSSLPrivateKey(bytes: [UInt8](pkcs8), format: .der) else {
            return nil
        }
        return (cert, key)
    }

    // MARK: - CA 构建

    private func buildCA() {
        guard let kp = generateRSA() else { fatalError("RSA generate failed") }
        caSecKey = kp.private
        guard let pubDER = SecKeyCopyExternalRepresentation(kp.public, nil) as Data?,
              let pkcs8 = pkcs8(fromPKCS1: SecKeyCopyExternalRepresentation(kp.private, nil) as? Data),
              let der = makeCert(subjectCN: "NCM Unlock CA",
                                 issuerCN: "NCM Unlock CA",
                                 issuerKey: kp.private,
                                 pubKeyDER: pubDER,
                                 san: nil,
                                 serial: randomSerial(),
                                 isCA: true) else {
            fatalError("CA build failed")
        }
        caCertDER = der
        caKeyPKCS8 = pkcs8
    }

    // MARK: - RSA

    private func generateRSA() -> (private: SecKey, public: SecKey)? {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var pub: SecKey?
        var priv: SecKey?
        guard SecKeyGeneratePair(attrs as CFDictionary, &pub, &priv) == errSecSuccess,
              let p = priv, let u = pub else { return nil }
        return (p, u)
    }

    private func randomSerial() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        // 保证正数（DER 整数首位不为 1）
        if bytes[0] & 0x80 != 0 { bytes[0] &= 0x7F }
        return Data(bytes)
    }

    // MARK: - 证书生成（手动 DER）

    /// 构造一张 X.509 v3 证书 DER（自签或由 issuerKey 签发）
    private func makeCert(subjectCN: String, issuerCN: String, issuerKey: SecKey,
                          pubKeyDER: Data, san: String?, serial: Data, isCA: Bool) -> Data? {
        // SubjectPublicKeyInfo
        let spki = derSequence([
            derSequence([derOID([1, 2, 840, 113_549, 1, 1, 1]), derNull()]), // rsaEncryption + NULL
            derBitString(pubKeyDER),
        ])

        let start = Date().addingTimeInterval(-60)
        let end = Date().addingTimeInterval(3600 * 24 * 365 * 10)

        var tbsParts: [Data] = []
        tbsParts.append(derContext(0, derInt(2)))                 // version [0] EXPLICIT = 2 (v3)
        tbsParts.append(derInt(serial))                           // serialNumber
        tbsParts.append(derSequence([derOID(sha256RSA), derNull()])) // signature algorithm
        tbsParts.append(name(issuerCN))                           // issuer
        tbsParts.append(derSequence([utcTime(start), utcTime(end)])) // validity
        tbsParts.append(name(subjectCN))                          // subject
        tbsParts.append(spki)                                     // subjectPublicKeyInfo

        // 扩展
        var exts: [Data] = []
        exts.append(basicConstraints(isCA: isCA))
        if let san = san { exts.append(subjectAltName(san)) }
        tbsParts.append(derContext(3, derSequence(exts)))         // extensions [3] EXPLICIT

        let tbs = derSequence(tbsParts)

        // RSA + SHA256 签名
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(issuerKey,
                                              .rsaSignatureMessagePKCS1v15SHA256,
                                              tbs as CFData, &error) as Data? else {
            return nil
        }

        return derSequence([
            tbs,
            derSequence([derOID(sha256RSA), derNull()]),
            derBitString(sig),
        ])
    }

    // MARK: - DER 基元

    private func derTag(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        if content.count < 128 {
            out.append(UInt8(content.count))
        } else {
            var len = content.count
            var lenBytes: [UInt8] = []
            while len > 0 {
                lenBytes.insert(UInt8(len & 0x7F), at: 0)
                len >>= 8
            }
            out.append(0x80 | UInt8(lenBytes.count))
            out.append(contentsOf: lenBytes)
        }
        out.append(content)
        return out
    }

    private func derSequence(_ parts: [Data]) -> Data {
        derTag(0x30, parts.reduce(Data()) { $0 + $1 })
    }

    private func derInt(_ bytes: Data) -> Data {
        var b = bytes
        if let f = b.first, (f & 0x80) != 0 { b.insert(0x00, at: 0) }
        if b.isEmpty { b = Data([0x00]) }
        return derTag(0x02, b)
    }

    private func derInt(_ value: UInt) -> Data {
        var v = value
        var bytes: [UInt8] = []
        if v == 0 { bytes = [0] }
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return derInt(Data(bytes))
    }

    private func derOID(_ arcs: [UInt]) -> Data {
        var body: [UInt8] = []
        let first = arcs[0] * 40 + arcs[1]
        body.append(UInt8(first))
        for a in arcs.dropFirst(2) {
            var x = a
            var tmp: [UInt8] = []
            tmp.append(UInt8(x & 0x7F))
            x >>= 7
            while x > 0 {
                tmp.insert(UInt8((x & 0x7F) | 0x80), at: 0)
                x >>= 7
            }
            body.append(contentsOf: tmp)
        }
        return derTag(0x06, Data(body))
    }

    private func derBitString(_ bytes: Data) -> Data {
        var content = Data([0x00]) // unused bits = 0
        content.append(bytes)
        return derTag(0x03, content)
    }

    private func derNull() -> Data { derTag(0x05, Data()) }

    private func derUTF8(_ s: String) -> Data { derTag(0x0C, Data(s.utf8)) }

    private func derBool(_ v: Bool) -> Data { derTag(0x01, Data([v ? 0xFF : 0x00])) }

    private func derOctet(_ content: Data) -> Data { derTag(0x04, content) }

    private func derContext(_ tag: UInt8, _ content: Data) -> Data { derTag(0xA0 | tag, content) }

    private func name(_ cn: String) -> Data {
        let attr = derSequence([derOID([2, 5, 4, 3]), derUTF8(cn)]) // CN
        let rdn = derTag(0x31, attr) // SET OF AttributeTypeAndValue
        return derSequence([rdn])
    }

    private func utcTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return derTag(0x17, Data(f.string(from: date).utf8))
    }

    private func basicConstraints(isCA: Bool) -> Data {
        let inner = derSequence([derBool(isCA)])
        return derSequence([derOID([2, 5, 29, 19]), derOctet(inner)])
    }

    private func subjectAltName(_ host: String) -> Data {
        // GeneralName dNSName [2] IMPLICIT IA5String
        let gn = derTag(0x82, Data(host.utf8))
        let inner = derSequence([gn])
        return derSequence([derOID([2, 5, 29, 17]), derOctet(inner)])
    }

    /// PKCS#1 DER -> PKCS#8 DER（NIOSSL 需要 PKCS#8）
    private func pkcs8(fromPKCS1 pkcs1: Data?) -> Data? {
        guard let pkcs1 = pkcs1 else { return nil }
        let alg = derSequence([derOID([1, 2, 840, 113_549, 1, 1, 1]), derNull()])
        return derSequence([derInt(0), alg, derOctet(pkcs1)])
    }
}
