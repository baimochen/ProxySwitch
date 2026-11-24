import Cocoa
import SystemConfiguration

// MARK: - 配置

final class Config {
    static let shared = Config()
    private let d = UserDefaults.standard

    var hotspotSSID: String { get { d.string(forKey: "hotspotSSID") ?? "11223344" } set { d.set(newValue, forKey: "hotspotSSID") } }
    var proxyHost: String { get { d.string(forKey: "proxyHost") ?? "10.23.216.132" } set { d.set(newValue, forKey: "proxyHost") } }
    var proxyPort: String { get { d.string(forKey: "proxyPort") ?? "7890" } set { d.set(newValue, forKey: "proxyPort") } }
    var serviceName: String { get { d.string(forKey: "serviceName") ?? "Wi-Fi" } set { d.set(newValue, forKey: "serviceName") } }
    var iconName: String { get { d.string(forKey: "iconName") ?? "key.fill" } set { d.set(newValue, forKey: "iconName") } }
    var waitSeconds: Int { get { d.object(forKey: "waitSeconds") as? Int ?? 9 } set { d.set(newValue, forKey: "waitSeconds") } }
    var autoReleaseOnSwitch: Bool { get { d.object(forKey: "autoReleaseOnSwitch") as? Bool ?? true } set { d.set(newValue, forKey: "autoReleaseOnSwitch") } }
    var syncPAC: Bool { get { d.object(forKey: "syncPAC") as? Bool ?? true } set { d.set(newValue, forKey: "syncPAC") } }
    var alsoSOCKS: Bool { get { d.object(forKey: "alsoSOCKS") as? Bool ?? false } set { d.set(newValue, forKey: "alsoSOCKS") } }
    var socksPort: String { get { d.string(forKey: "socksPort") ?? "7891" } set { d.set(newValue, forKey: "socksPort") } }
    var hotspotPrefix: String { get { d.string(forKey: "hotspotPrefix") ?? "10.23.216." } set { d.set(newValue, forKey: "hotspotPrefix") } }
    var autoMode: Bool { get { d.object(forKey: "autoMode") as? Bool ?? true } set { d.set(newValue, forKey: "autoMode") } }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let config = Config.shared
    private var onSave: () -> Void

    private var ssidField: NSTextField!
    private var hostField: NSTextField!
    private var portField: NSTextField!
    private var serviceField: NSTextField!
    private var iconPopup: NSPopUpButton!
    private var waitField: NSTextField!
    private var prefixField: NSTextField!
    private var socksPortField: NSTextField!
    private var autoReleaseCheck: NSButton!
    private var syncPACCheck: NSButton!
    private var socksCheck: NSButton!
    private var autoModeCheck: NSButton!

    private let iconChoices: [(String, String)] = [
        ("key.fill", "钥匙"), ("wifi", "Wi-Fi"), ("lock.fill", "锁"),
        ("shield.fill", "盾牌"), ("network", "网络"), ("globe", "地球"),
        ("antenna.radiowaves.left.and.right", "信号"), ("bolt.fill", "闪电")
    ]

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "ProxySwitch 设置"
        w.center()
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let h = NSStackView(views: [label, control])
        h.orientation = .horizontal
        h.spacing = 10
        h.alignment = .centerY
        return h
    }

    private func hint(_ text: String) -> NSView {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func buildUI() {
        ssidField = NSTextField(string: "")
        hostField = NSTextField(string: "")
        portField = NSTextField(string: "")
        serviceField = NSTextField(string: "")
        waitField = NSTextField(string: "")
        prefixField = NSTextField(string: "")
        socksPortField = NSTextField(string: "")
        for f in [ssidField, hostField, portField, serviceField, waitField, prefixField, socksPortField] {
            f!.widthAnchor.constraint(equalToConstant: 200).isActive = true
        }

        iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (symbol, title) in iconChoices {
            iconPopup.addItem(withTitle: title)
            iconPopup.lastItem?.representedObject = symbol
        }

        autoModeCheck = NSButton(checkboxWithTitle: "自动检测：连上热点就开代理，离开就关", target: nil, action: nil)
        autoReleaseCheck = NSButton(checkboxWithTitle: "切换到别的 Wi-Fi 时自动释放代理", target: nil, action: nil)
        syncPACCheck = NSButton(checkboxWithTitle: "设置代理时关闭「自动配置代理」(PAC)", target: nil, action: nil)
        socksCheck = NSButton(checkboxWithTitle: "同时设置 SOCKS 代理", target: nil, action: nil)

        let save = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [
            row("热点 / Wi-Fi 名称", ssidField),
            row("代理服务器", hostField),
            row("代理端口", portField),
            row("热点网段前缀", prefixField),
            hint("  用本机 IP 前缀判断是否已连上热点（例：10.23.216.）"),
            row("网络服务名", serviceField),
            hint("  系统设置 → 网络 里那个服务的名字，一般是 Wi-Fi"),
            row("等待连接秒数", waitField),
            row("菜单栏图标", iconPopup),
            row("SOCKS 端口", socksPortField),
            autoModeCheck,
            autoReleaseCheck,
            syncPACCheck,
            socksCheck,
            buttons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        window?.contentView = content

        let fit = stack.fittingSize
        window?.setContentSize(NSSize(width: max(500, fit.width + 42), height: max(300, fit.height + 42)))
    }

    private func loadValues() {
        ssidField.stringValue = config.hotspotSSID
        hostField.stringValue = config.proxyHost
        portField.stringValue = config.proxyPort
        serviceField.stringValue = config.serviceName
        prefixField.stringValue = config.hotspotPrefix
        waitField.stringValue = String(config.waitSeconds)
        socksPortField.stringValue = config.socksPort
        autoModeCheck.state = config.autoMode ? .on : .off
        autoReleaseCheck.state = config.autoReleaseOnSwitch ? .on : .off
        syncPACCheck.state = config.syncPAC ? .on : .off
        socksCheck.state = config.alsoSOCKS ? .on : .off
        if let idx = iconChoices.firstIndex(where: { $0.0 == config.iconName }) {
            iconPopup.selectItem(at: idx)
        } else {
            iconPopup.selectItem(at: 0)
        }
    }

    override func showWindow(_ sender: Any?) {
        loadValues()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func saveClicked() {
        let ssid = ssidField.stringValue.trimmingCharacters(in: .whitespaces)
        if !ssid.isEmpty { config.hotspotSSID = ssid }
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        if !host.isEmpty { config.proxyHost = host }
        let port = portField.stringValue.trimmingCharacters(in: .whitespaces)
        if !port.isEmpty { config.proxyPort = port }
        let service = serviceField.stringValue.trimmingCharacters(in: .whitespaces)
        if !service.isEmpty { config.serviceName = service }
        let prefix = prefixField.stringValue.trimmingCharacters(in: .whitespaces)
        if !prefix.isEmpty { config.hotspotPrefix = prefix }
        config.waitSeconds = max(3, Int(waitField.stringValue) ?? 9)
        let socksPort = socksPortField.stringValue.trimmingCharacters(in: .whitespaces)
        if !socksPort.isEmpty { config.socksPort = socksPort }
        if let sym = iconPopup.selectedItem?.representedObject as? String { config.iconName = sym }
        config.autoMode = autoModeCheck.state == .on
        config.autoReleaseOnSwitch = autoReleaseCheck.state == .on
        config.syncPAC = syncPACCheck.state == .on
        config.alsoSOCKS = socksCheck.state == .on
        onSave()
        window?.close()
    }

    @objc private func cancelClicked() { window?.close() }

    func refreshFromConfig() { loadValues() }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - 主程序

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let config = Config.shared
    private let ns = "/usr/sbin/networksetup"
    private let ipconfig = "/usr/sbin/ipconfig"
    private var settingsController: SettingsWindowController?
    private let queue = DispatchQueue(label: "com.dsh.proxyswitch.monitor")
    private var autoOpened = false
    private var suppressAuto = false
    private var lastIP = ""
    private var store: SCDynamicStore?
    private var checkWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyIcon()
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()
        setupNetworkMonitor()
        scheduleCheck(0.5)
        queue.async {
            let ip = self.currentIP()
            if !ip.hasPrefix(self.config.hotspotPrefix) && self.currentProxyServer() == self.config.proxyHost {
                self.proxyOff()
                DispatchQueue.main.async { self.buildMenu() }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { buildMenu() }

    private func applyIcon() {
        let img = NSImage(systemSymbolName: config.iconName, accessibilityDescription: "ProxySwitch")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    private func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func currentProxyServer() -> String {
        for line in run(ns, ["-getwebproxy", config.serviceName]).split(separator: "\n") {
            if line.hasPrefix("Server:") {
                return line.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private func proxyEnabled() -> Bool {
        run(ns, ["-getwebproxy", config.serviceName]).contains("Enabled: Yes")
    }

    private func currentIP() -> String {
        let out = run(ipconfig, ["getifaddr", "en0"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "未连接" : out
    }

    private func onHotspot() -> Bool {
        currentIP().hasPrefix(config.hotspotPrefix)
    }

    private func savedNetworks() -> [String] {
        run(ns, ["-listpreferredwirelessnetworks", "en0"])
            .split(separator: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func proxyOn() {
        if config.syncPAC { _ = run(ns, ["-setautoproxystate", config.serviceName, "off"]) }
        _ = run(ns, ["-setwebproxy", config.serviceName, config.proxyHost, config.proxyPort])
        _ = run(ns, ["-setsecurewebproxy", config.serviceName, config.proxyHost, config.proxyPort])
        if config.alsoSOCKS {
            _ = run(ns, ["-setsocksfirewallproxy", config.serviceName, config.proxyHost, config.socksPort])
        }
    }

    private func proxyOff() {
        _ = run(ns, ["-setwebproxystate", config.serviceName, "off"])
        _ = run(ns, ["-setsecurewebproxystate", config.serviceName, "off"])
        _ = run(ns, ["-setsocksfirewallproxystate", config.serviceName, "off"])
    }

    // MARK: 自动监控

    // 注册系统网络配置变化通知（事件驱动，不轮询）
    private func setupNetworkMonitor() {
        var context = SCDynamicStoreContext(version: 0,
                                            info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info = info else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            me.scheduleCheck()
        }
        guard let store = SCDynamicStoreCreate(nil, "com.dsh.proxyswitch" as CFString, callback, &context) else { return }
        let keys = ["State:/Network/Global/IPv4", "State:/Network/Interface/en0/IPv4"] as CFArray
        SCDynamicStoreSetNotificationKeys(store, keys, nil)
        if let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        self.store = store
    }

    // 合并短时间内的多次变化（Wi-Fi 连接时 IP 会变好几次）
    private func scheduleCheck(_ delay: TimeInterval = 0.6) {
        checkWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.checkNetwork() }
        checkWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func checkNetwork() {
        queue.async {
            let ip = self.currentIP()
            let match = ip.hasPrefix(self.config.hotspotPrefix)
            let on = self.proxyEnabled()
            let ipChanged = (ip != self.lastIP)
            if ipChanged {
                self.lastIP = ip
                self.suppressAuto = false
            }
            var changed = ipChanged

            if self.config.autoMode && !self.suppressAuto {
                if match {
                    if !on {
                        self.proxyOn()
                        changed = true
                    }
                    self.autoOpened = true
                } else if on && self.autoOpened {
                    self.proxyOff()
                    self.autoOpened = false
                    changed = true
                } else if !on {
                    self.autoOpened = false
                }
            }

            if changed {
                DispatchQueue.main.async { self.buildMenu() }
            }
        }
    }

    private func buildMenu() {
        menu.removeAllItems()

        let ip = currentIP()
        let onProxy = proxyEnabled()
        let match = ip.hasPrefix(config.hotspotPrefix)

        let status = NSMenuItem(title: "代理：\(onProxy ? "开" : "关")    IP：\(ip)   \(match ? "✓ 热点" : "非热点")",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let summary = NSMenuItem(title: "\(config.proxyHost):\(config.proxyPort) → \(config.hotspotSSID)", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())

        let auto = NSMenuItem(title: "自动检测：\(config.autoMode ? "开" : "关")", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self
        auto.state = config.autoMode ? .on : .off
        menu.addItem(auto)

        let onItem = NSMenuItem(title: "手动开代理", action: #selector(manualProxyOn), keyEquivalent: "")
        onItem.target = self
        menu.addItem(onItem)

        let offItem = NSMenuItem(title: "手动关代理", action: #selector(manualProxyOff), keyEquivalent: "")
        offItem.target = self
        menu.addItem(offItem)

        menu.addItem(.separator())

        let wifiItem = NSMenuItem(title: "切换 Wi-Fi", action: nil, keyEquivalent: "")
        let wifiMenu = NSMenu()
        for name in savedNetworks() {
            let item = NSMenuItem(title: name, action: #selector(joinNetwork(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            wifiMenu.addItem(item)
        }
        wifiMenu.addItem(.separator())
        let openWifi = NSMenuItem(title: "打开 Wi-Fi 设置…", action: #selector(openWiFiSettings), keyEquivalent: "")
        openWifi.target = self
        wifiMenu.addItem(openWifi)
        wifiItem.submenu = wifiMenu
        menu.addItem(wifiItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    private func showAlert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .informational
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc private func toggleAuto() {
        config.autoMode.toggle()
        autoOpened = false
        suppressAuto = false
        buildMenu()
        settingsController?.refreshFromConfig()
        scheduleCheck(0.2)
    }

    @objc private func manualProxyOn() {
        queue.async {
            self.proxyOn()
            self.autoOpened = false
            self.suppressAuto = false
            DispatchQueue.main.async {
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
            }
        }
    }

    @objc private func manualProxyOff() {
        queue.async {
            self.proxyOff()
            self.autoOpened = false
            self.suppressAuto = true
            DispatchQueue.main.async {
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
            }
        }
    }

    @objc private func joinNetwork(_ sender: NSMenuItem) {
        guard let ssid = sender.representedObject as? String else { return }
        queue.async {
            if self.config.autoReleaseOnSwitch { self.proxyOff() }
            let out = self.run(self.ns, ["-setairportnetwork", "en0", ssid])
            sleep(UInt32(self.config.waitSeconds))
            let failed = out.contains("Failed") || out.lowercased().contains("error")
            DispatchQueue.main.async {
                self.buildMenu()
                if failed {
                    self.showAlert("自动切换失败", "系统不允许脚本直接切换 Wi-Fi。\n请点菜单栏的 Wi-Fi 图标手动选择「\(ssid)」，连上后会自动开代理。")
                }
            }
        }
    }

    @objc private func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController { [weak self] in
                self?.applyIcon()
                self?.buildMenu()
                self?.scheduleCheck(0.2)
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeFirstResponder(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
