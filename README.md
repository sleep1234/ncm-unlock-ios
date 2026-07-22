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

## 云编译（GitHub Actions，免签）

本仓库的 CI（`build.yml`）默认走 **免签构建**：不需要任何付费证书或 Secrets，直接产出
未签名的 `NCMUnlock.ipa`，供越狱机用 **TrollStore** 安装（TrollStore 会按内嵌的
`packet-tunnel-provider` 等 entitlements 重新签名）。

Fork / push 到 GitHub 后，在 Actions 页手动触发 `Build IPA`（或 push 到 `main` / `vpn` 分支自动触发）。
产物在 Artifacts 里下载：`NCMUnlock-unsigned.ipa`。

> 若你坚持要 Apple 官方签名的 IPA（非越狱机、企业/Ad-Hoc 分发），再在仓库 Secrets
> 配置 `P12_BASE64` / `P12_PASSWORD` / `APP_PROFILE_BASE64` / `TUNNEL_PROFILE_BASE64` /
> `TEAM_ID` / `KEYCHAIN_PASSWORD`，并把 `build.yml` 的 build 步改成 `archive` + `exportArchive`
>（`method=ad-hoc`）。注意 **NetworkExtension 的 `packet-tunnel-provider` 授权需要付费开发者账号**。

## 真机使用前置（越狱机，缺一不可）

1. 用 **TrollStore** 安装 `NCMUnlock-unsigned.ipa`（TrollStore 会自动按 entitlements 重签）。
2. 开启**关闭证书锁定**的插件（SSL Kill Switch 2 / Liberty Lite 的 block TLS pinning）。
   这一步会禁用 TLS 校验，因此本工程运行时自签的 MITM 证书会被直接信任，**无需手动安装 CA**
   （现象同此前日志里的 `interface3 does not trust` 即由此解决）。
   - 若你不想装 SSL Kill Switch，则需把本 App 生成的 CA 证书（`CertAuthority.exportCACertificate()`）
     导出为 .pem/.mobileconfig、安装到系统，并在「设置 → 通用 → 关于本机 → 证书信任设置」完全信任。
3. 打开 NCM Unlock App，开启开关；网易云后台划掉重开，播 VIP 歌验证。
4. 看 App 日志 / 设备日志里有没有 `[ncm][ok] ... -> unlocked` 确认生效。

## 已知待迭代点

- `ProxyServer` 的 CONNECT 与 TLS ClientHello 同段到达时的重新喂入逻辑，需在真机确认。
- `CertAuthority` 的 ASN.1 需真机验证叶子证书是否被系统接受（重点：SAN / BasicConstraints）。
- 非网易云流量目前走纯 TCP 透传；确认不会因代理设置造成其他 App 异常。
