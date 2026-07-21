# NCM Unlock (iOS)

网易云音乐 iOS 端解锁工具：一个独立的 **NetworkExtension（透明隧道）App**，内置本地 MITM 代理，
把 `player/url` 等接口的受限音源改写为 [GD Studio](https://music-api.gdstudio.xyz/api.php) 的完整播放地址。
逻辑移植自同一工作区里的安卓 `ncm-unlock` 模块（`EAPIHook` / `CdnHook` / `DownloadMD5Hook`）。

> ⚠️ 本工程在本机无法编译（无 macOS / Xcode），靠 GitHub Actions 的构建日志迭代。
> 透明隧道内的 TLS MITM 是最易出错的部分，需要真机验证。

## 架构

```
网易云 App
   │  HTTPS 请求（interface3.music.163.com ...）
   ▼
NEPacketTunnelProvider  （透明隧道，注入 NEProxySettings -> 127.0.0.1:8899）
   │
   ▼
ProxyServer (SwiftNIO)   ── 对网易云主机做 TLS MITM（CA 由 CertAuthority 运行时签发）
   │  解析 HTTPS 请求
   ▼
handleRequest  ── POST 且命中解锁接口：转发到真实服务器（URLSession，正常校验证书）
                └─ EapiCrypto 解密响应 -> EAPIHandler 清 fee/flag + 换 GD 源 -> 回包
```

## 目录

| 文件 | 作用 |
| --- | --- |
| `NCMUnlockTunnel/Constants.swift` | 网易云主机 / 解锁接口 / GD API 基址 |
| `NCMUnlockTunnel/Crypto.swift` | eapi 信封 AES-128-ECB 加解密（CommonCrypto，零三方依赖） |
| `NCMUnlockTunnel/GDStudio.swift` | GD Studio 取完整播放地址（带缓存） |
| `NCMUnlockTunnel/CertStore.swift` | 自签名 CA + 叶子证书（手动 ASN.1 DER） |
| `NCMUnlockTunnel/EAPIHandler.swift` | 解密响应后清限制 + 换源 |
| `NCMUnlockTunnel/ProxyServer.swift` | SwiftNIO MITM 代理（CONNECT / TLS / 转发 / 透传） |
| `NCMUnlockTunnel/PacketTunnelProvider.swift` | 隧道：注入代理设置 + 启动代理 |
| `NCMUnlock/...` | 主 App：开关隧道的 UI |
| `project.yml` | XcodeGen 工程描述（两个 target + SPM 依赖） |
| `.github/workflows/build.yml` | GitHub Actions 云编译 IPA |

## 本地构建（macOS）

```bash
brew install xcodegen
xcodegen generate
open NCMUnlock.xcodeproj
# 用你的开发者证书签名两个 target 后跑真机
```

## 云编译（GitHub Actions）

Fork / push 到 GitHub 后，在 Actions 页手动触发 `Build IPA`。
需要仓库 **Secrets**（Settings → Secrets → Actions）：

| Secret | 说明 |
| --- | --- |
| `P12_BASE64` | 你的 iOS 分发证书（.p12）base64 |
| `P12_PASSWORD` | p12 导出密码 |
| `APP_PROFILE_BASE64` | 主 App 的 .mobileprovision（bundle id `com.ncm.unlock`）base64 |
| `TUNNEL_PROFILE_BASE64` | 隧道扩展的 .mobileprovision（`com.ncm.unlock.tunnel`）base64 |
| `TEAM_ID` | Apple Developer Team ID |
| `KEYCHAIN_PASSWORD` | 给 CI 用的临时 keychain 密码（随便设） |

> **NetworkExtension 需要付费开发者账号**（免费 Apple ID 没有 `packet-tunnel-provider` 授权）。
> 若你只有免费账号，需改用「本地 HTTP 代理 App + 手动设置 WiFi 代理」的形态（不含 NetworkExtension）。

## 真机使用前置（缺一不可）

1. 安装 IPA（AltStore / TrollStore / 自签）。
2. **越狱设备**：装并开启「关闭证书锁定」的插件（SSL Kill Switch 2 / Liberty Lite 的 block TLS pinning）。
   否则网易云会拒掉我们的 MITM 证书（现象同此前日志里的 `interface3 does not trust`）。
3. iOS「设置 → 通用 → 关于本机 → 证书信任设置」把本 App 生成的 CA **完全信任**打开
   （本工程会在隧道启动时把 CA 证书 DER 通过 App Group / 日志导出，需手动安装）。
4. 打开 NCM Unlock App，开启开关；网易云后台划掉重开，播 VIP 歌验证。

## 已知待迭代点

- `ProxyServer` 的 CONNECT 与 TLS ClientHello 同段到达时的重新喂入逻辑，需在真机确认。
- `CertAuthority` 的 ASN.1 需真机验证叶子证书是否被系统接受（重点：SAN / BasicConstraints）。
- 非网易云流量目前走纯 TCP 透传；确认不会因代理设置造成其他 App 异常。
