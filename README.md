# NCM Unlock iOS

解锁网易云音乐 VIP 歌曲的 iOS Tweak。

## 功能特性

- ✅ 解锁 VIP 歌曲播放
- ✅ 支持多种音质选择（128k/192k/320k/FLAC）
- ✅ 显示替换提示 Toast
- ✅ 稳定音源：网易云、Joox、Bilibili
- ✅ 在设置页面添加模块设置入口

## 系统要求

- iOS 14.0+
- 已越狱设备
- 安装 MobileSubstrate (Cydia Substrate)

## 编译环境

### macOS (推荐)

1. 安装 Theos：
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

2. 克隆项目：
```bash
git clone https://github.com/sleep1234/ncm-unlock-ios.git
cd ncm-unlock-ios
```

3. 编译：
```bash
./build.sh
```

### Linux (WSL/Docker)

1. 安装 Theos Linux 版本
2. 使用交叉编译工具链

### Windows

1. 安装 WSL2 + Ubuntu
2. 在 WSL 中安装 Theos
3. 使用交叉编译

## 安装方法

### 方法一：通过 Cydia/Sileo

1. 添加源：`https://your-repo.com`
2. 搜索 "NCM Unlock"
3. 安装

### 方法二：手动安装

1. 将 `.deb` 文件传输到 iPhone
2. 使用 Filza 文件管理器打开
3. 点击安装
4. 重启网易云音乐

### 方法三：通过 SSH

```bash
# 传输文件
scp com.raincat.ncm-unlock-ios_*.deb root@iphone-ip:/tmp/

# SSH 到 iPhone
ssh root@iphone-ip

# 安装
dpkg -i /tmp/com.raincat.ncm-unlock-ios_*.deb

# 重启网易云音乐
killall -9 CloudMusic
```

## 使用方法

1. 打开网易云音乐
2. 进入 **设置** 页面
3. 滚动到底部，找到 **NCM Unlock 设置**
4. 点击进入，选择音质和其他选项

## 音质说明

| 音质 | 码率 | 说明 |
|------|------|------|
| 标准 | 128kbps | 默认音质，兼容性最好 |
| 较高 | 192kbps | 平衡音质和流量 |
| 极高 | 320kbps | 高品质，推荐 |
| 无损 | FLAC | 最高品质，需要会员源 |

## 音源说明

- **网易云**：官方 API，最稳定
- **Joox**：需要代理服务器
- **Bilibili**：备用音源

## 常见问题

### Q: 安装后没有效果？

A: 确保：
1. 设备已越狱
2. MobileSubstrate 已安装
3. 重启了网易云音乐

### Q: 部分歌曲无法播放？

A: 可能原因：
1. 该歌曲在所有音源都不可用
2. 网络问题
3. 尝试切换音质

### Q: 如何卸载？

A: 通过 Cydia/Sileo 卸载，或：
```bash
dpkg -r com.raincat.ncm-unlock-ios
```

## 开发说明

### 项目结构

```
ncm-unlock-ios/
├── Makefile              # Theos 编译配置
├── control               # deb 包信息
├── build.sh              # 编译脚本
├── Tweak/
│   ├── Tweak.x          # 主 Hook 文件
│   ├── NCMUnlockAPI.h   # 解锁 API 头文件
│   ├── NCMUnlockAPI.m   # 解锁 API 实现
│   ├── SettingsHelper.h # 设置管理头文件
│   └── SettingsHelper.m # 设置管理实现
└── Resources/            # 资源文件
```

### 主要 Hook 点

1. `NSURLSession` - 拦截网络请求
2. `NCMSettingViewController` - 添加设置入口

### 添加新音源

在 `NCMUnlockAPI.m` 中添加新的音源方法：

```objc
- (void)tryNewSource:(NSString *)songId completion:(void (^)(NSString *url, NSString *quality))completion {
    // 实现新音源逻辑
}
```

## 许可证

MIT License

## 致谢

- [Theos](https://theos.dev/) - iOS 逆向开发框架
- [UnblockNeteaseMusic](https://github.com/nondanee/UnblockNeteaseMusic) - 音源参考

## 联系方式

- 作者：毛利老王
- GitHub：https://github.com/sleep1234/ncm-unlock-ios
