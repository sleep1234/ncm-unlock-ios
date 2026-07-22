import UIKit
import NetworkExtension

class ViewController: UIViewController {

    private let toggle = UISwitch()
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "NCM Unlock"
        setupUI()
        registerStatusObserver()
        loadManager()
    }

    private func setupUI() {
        statusLabel.text = "状态：未连接"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 17, weight: .medium)

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)

        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        hintLabel.textColor = .secondaryLabel
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.text = "开启后，网易云音乐的音源会被改写为 GD Studio 解锁地址。\n需在「设置 → 通用 → 关于本机 → 证书信任设置」完全信任本 App 的 CA，\n且越狱设备需关闭证书锁定（SSL Kill Switch 等）。"

        let stack = UIStackView(arrangedSubviews: [statusLabel, toggle, hintLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func loadManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            self?.manager = managers?.first ?? self?.makeManager()
            self?.registerStatusObserver()
            self?.refreshStatus()
        }
    }

    private func makeManager() -> NETunnelProviderManager {
        let m = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.ncm.unlock.tunnel" // 与 tunnel target 的 bundle id 对应
        proto.serverAddress = "NCM Unlock"
        m.protocolConfiguration = proto
        m.localizedDescription = "NCM Unlock"
        m.isEnabled = true
        return m
    }

    private func refreshStatus() {
        guard let conn = manager?.connection else {
            DispatchQueue.main.async { self.statusLabel.text = "状态：未连接" }
            return
        }
        let status = conn.status
        DispatchQueue.main.async {
            switch status {
            case .connected:
                self.toggle.isOn = true
                self.statusLabel.text = "状态：已连接"
            case .connecting:
                self.toggle.isOn = true
                self.statusLabel.text = "状态：连接中…"
            case .disconnecting:
                self.statusLabel.text = "状态：断开中…"
            case .disconnected:
                self.toggle.isOn = false
                self.statusLabel.text = "状态：未连接"
            case .invalid:
                self.toggle.isOn = false
                self.statusLabel.text = "状态：未连接"
            @unknown default:
                self.statusLabel.text = "状态：未知"
            }
        }
    }

    /// 注册 NEVPNStatusDidChange 监听，确保 UI 实时反映隧道连接状态。
    /// 先移除旧 observer 再添加，避免重复注册；object 使用当前 manager 的 connection。
    private func registerStatusObserver() {
        if let old = statusObserver {
            NotificationCenter.default.removeObserver(old)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager?.connection,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    @objc private func toggleChanged() {
        if toggle.isOn {
            startTunnel()
        } else {
            stopTunnel()
        }
    }

    private func startTunnel() {
        guard let manager = manager else { return }
        manager.isEnabled = true
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                self?.showError(error)
                return
            }
            self?.loadAndStart()
        }
    }

    private func loadAndStart() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            if let error = error {
                self.showError(error)
                return
            }
            guard let m = managers?.first else {
                let notFound = NSError(
                    domain: "ncm",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "未找到已保存的 VPN 配置，请重试"]
                )
                self.showError(notFound)
                return
            }
            self.manager = m
            self.registerStatusObserver()
            self.refreshStatus()
            if m.isEnabled {
                do {
                    try m.connection.startVPNTunnel()
                } catch {
                    self.showError(error)
                }
            } else {
                m.isEnabled = true
                m.saveToPreferences { error in
                    if let error = error {
                        self.showError(error)
                        return
                    }
                    do {
                        try m.connection.startVPNTunnel()
                    } catch {
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func stopTunnel() {
        manager?.connection.stopVPNTunnel()
    }

    private func showError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "错误", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            self.present(alert, animated: true)
        }
    }

    deinit {
        if let o = statusObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }
}
