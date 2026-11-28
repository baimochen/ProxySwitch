import Cocoa
import SystemConfiguration

// MARK: - 配置

final class Config {
    static let shared = Config()
    private let d = UserDefaults.standard

    var hotspotSSID: String { get { d.string(forKey: "hotspotSSID") ?? "" } set { d.set(newValue, forKey: "hotspotSSID") } }
    var proxyHost: String { get { d.string(forKey: "proxyHost") ?? "" } set { d.set(newValue, forKey: "proxyHost") } }
    var proxyPort: String { get { d.string(forKey: "proxyPort") ?? "7890" } set { d.set(newValue, forKey: "proxyPort") } }
    var serviceName: String { get { d.string(forKey: "serviceName") ?? "Wi-Fi" } set { d.set(newValue, forKey: "serviceName") } }
    var iconName: String { get { d.string(forKey: "iconName") ?? "key.fill" } set { d.set(newValue, forKey: "iconName") } }
    var waitSeconds: Int { get { d.object(forKey: "waitSeconds") as? Int ?? 9 } set { d.set(newValue, forKey: "waitSeconds") } }
    var autoReleaseOnSwitch: Bool { get { d.object(forKey: "autoReleaseOnSwitch") as? Bool ?? true } set { d.set(newValue, forKey: "autoReleaseOnSwitch") } }
    var syncPAC: Bool { get { d.object(forKey: "syncPAC") as? Bool ?? true } set { d.set(newValue, forKey: "syncPAC") } }
    var alsoSOCKS: Bool { get { d.object(forKey: "alsoSOCKS") as? Bool ?? false } set { d.set(newValue, forKey: "alsoSOCKS") } }
    var socksPort: String { get { d.string(forKey: "socksPort") ?? "7891" } set { d.set(newValue, forKey: "socksPort") } }
    var hotspotPrefix: String { get { d.string(forKey: "hotspotPrefix") ?? "" } set { d.set(newValue, forKey: "hotspotPrefix") } }
    var autoMode: Bool { get { d.object(forKey: "autoMode") as? Bool ?? true } set { d.set(newValue, forKey: "autoMode") } }

    var isConfigured: Bool {
        !proxyHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !hotspotPrefix.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isValidPort(_ raw: String) -> Bool {
        guard let port = Int(raw), (1...65535).contains(port) else { return false }
        return true
    }
}

// MARK: - 网络状态快照

private struct NetworkSnapshot {
    var ip: String = "检测中…"
    var proxyEnabled: Bool = false
    var savedNetworks: [String] = []
    var interfaceName: String = "en0"
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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
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
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
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
        ssidField.placeholderString = "可选，仅用于菜单展示"
        hostField = NSTextField(string: "")
        hostField.placeholderString = "例：172.20.10.1"
        portField = NSTextField(string: "")
        portField.placeholderString = "1–65535（默认 7890）"
        serviceField = NSTextField(string: "")
        serviceField.placeholderString = "默认 Wi-Fi"
        waitField = NSTextField(string: "")
        waitField.placeholderString = "3–60"
        prefixField = NSTextField(string: "")
        prefixField.placeholderString = "例：172.20.10."
        socksPortField = NSTextField(string: "")
        socksPortField.placeholderString = "1–65535（默认 7891）"

        for f in [ssidField, hostField, portField, serviceField, waitField, prefixField, socksPortField] {
            f!.widthAnchor.constraint(equalToConstant: 210).isActive = true
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
            row("热点名称（展示用）", ssidField),
            row("代理服务器", hostField),
            row("HTTP/HTTPS 端口", portField),
            row("热点网段前缀", prefixField),
            hint("  用本机 IP 前缀判断是否已连上热点（例：172.20.10.）"),
            row("网络服务名", serviceField),
            hint("  系统设置 → 网络 里对应服务的名称，一般是 Wi-Fi"),
            row("切网后等待秒数", waitField),
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
        window?.setContentSize(NSSize(width: max(520, fit.width + 42), height: max(300, fit.height + 42)))
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

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "设置无效"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        if let win = window {
            alert.beginSheetModal(for: win)
        } else {
            alert.runModal()
        }
    }

    @objc private func saveClicked() {
        let port = portField.stringValue.trimmingCharacters(in: .whitespaces)
        if !Config.isValidPort(port) {
            showValidationError("HTTP/HTTPS 端口必须是 1–65535 之间的整数。")
            return
        }
        let socksPort = socksPortField.stringValue.trimmingCharacters(in: .whitespaces)
        if socksCheck.state == .on && !Config.isValidPort(socksPort) {
            showValidationError("SOCKS 端口必须是 1–65535 之间的整数。")
            return
        }

        let service = serviceField.stringValue.trimmingCharacters(in: .whitespaces)
        config.hotspotSSID = ssidField.stringValue.trimmingCharacters(in: .whitespaces)
        config.proxyHost = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        config.proxyPort = port
        config.serviceName = service.isEmpty ? "Wi-Fi" : service
        config.hotspotPrefix = prefixField.stringValue.trimmingCharacters(in: .whitespaces)
        config.waitSeconds = min(60, max(3, Int(waitField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 9))
        if Config.isValidPort(socksPort) {
            config.socksPort = socksPort
        }
        if let sym = iconPopup.selectedItem?.representedObject as? String {
            config.iconName = sym
        }
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

    // 所有可变网络状态仅在 queue 上读写；snapshot 通过主线程更新菜单
    private let queue = DispatchQueue(label: "com.dsh.proxyswitch.monitor")
    private var autoOpened = false
    private var suppressAuto = false
    private var lastIP = ""
    private var snapshot = NetworkSnapshot()
    private var monitoredInterface = ""

    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?
    private var checkWorkItem: DispatchWorkItem?
    private var isMenuOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyIcon()
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()

        queue.async {
            let iface = self.resolveInterface(for: self.config.serviceName)
            let snap = self.collectSnapshot(interface: iface)
            if self.config.isConfigured,
               !snap.ip.hasPrefix(self.config.hotspotPrefix),
               self.currentProxyServer() == self.config.proxyHost {
                _ = self.proxyOff()
            }
            let updatedSnap = self.collectSnapshot(interface: iface)
            DispatchQueue.main.async {
                self.snapshot = updatedSnap
                self.setupNetworkMonitor(interface: iface)
                self.buildMenu()
                self.scheduleCheck(0.4)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        buildMenu()
        refreshSnapshotAsync()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func applyIcon() {
        let img = NSImage(systemSymbolName: config.iconName, accessibilityDescription: "ProxySwitch")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    // MARK: 系统命令执行（带超时保护）

    private func run(_ tool: String, _ args: [String], timeout: TimeInterval = 5.0) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }

        do {
            try p.run()
        } catch {
            return (-1, "")
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 0.5)
            return (-2, "Command timed out")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func resolveInterface(for serviceName: String) -> String {
        let res = run(ns, ["-listallhardwareports"])
        guard res.status == 0 else { return "en0" }

        let lines = res.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var matchedPort = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Hardware Port:") {
                let portName = trimmed.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
                matchedPort = (portName == serviceName)
            } else if matchedPort && trimmed.hasPrefix("Device:") {
                let dev = trimmed.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if !dev.isEmpty { return dev }
                matchedPort = false
            }
        }
        return "en0"
    }

    private func currentProxyServer() -> String {
        let res = run(ns, ["-getwebproxy", config.serviceName])
        for line in res.output.split(separator: "\n") {
            if line.hasPrefix("Server:") {
                return line.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private func proxyEnabled() -> Bool {
        run(ns, ["-getwebproxy", config.serviceName]).output.contains("Enabled: Yes")
    }

    private func currentIP(interface: String) -> String {
        let res = run(ipconfig, ["getifaddr", interface])
        let out = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (res.status == 0 && !out.isEmpty) ? out : "未连接"
    }

    private func savedNetworks(interface: String) -> [String] {
        run(ns, ["-listpreferredwirelessnetworks", interface]).output
            .split(separator: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func collectSnapshot(interface: String) -> NetworkSnapshot {
        NetworkSnapshot(
            ip: currentIP(interface: interface),
            proxyEnabled: proxyEnabled(),
            savedNetworks: savedNetworks(interface: interface),
            interfaceName: interface
        )
    }

    @discardableResult
    private func proxyOn() -> Bool {
        guard !config.proxyHost.trimmingCharacters(in: .whitespaces).isEmpty,
              Config.isValidPort(config.proxyPort) else { return false }
        if config.syncPAC {
            _ = run(ns, ["-setautoproxystate", config.serviceName, "off"])
        }
        let r1 = run(ns, ["-setwebproxy", config.serviceName, config.proxyHost, config.proxyPort])
        let r2 = run(ns, ["-setsecurewebproxy", config.serviceName, config.proxyHost, config.proxyPort])
        if config.alsoSOCKS && Config.isValidPort(config.socksPort) {
            _ = run(ns, ["-setsocksfirewallproxy", config.serviceName, config.proxyHost, config.socksPort])
        }
        return r1.status == 0 && r2.status == 0
    }

    @discardableResult
    private func proxyOff() -> Bool {
        let r1 = run(ns, ["-setwebproxystate", config.serviceName, "off"])
        let r2 = run(ns, ["-setsecurewebproxystate", config.serviceName, "off"])
        _ = run(ns, ["-setsocksfirewallproxystate", config.serviceName, "off"])
        return r1.status == 0 && r2.status == 0
    }

    // MARK: 自动监控

    private func setupNetworkMonitor(interface: String) {
        if monitoredInterface == interface && store != nil { return }
        if let src = storeSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            storeSource = nil
        }
        store = nil
        monitoredInterface = interface

        var context = SCDynamicStoreContext(version: 0,
                                            info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info = info else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            me.scheduleCheck()
        }
        guard let newStore = SCDynamicStoreCreate(nil, "com.dsh.proxyswitch" as CFString, callback, &context) else { return }
        let keys = ["State:/Network/Global/IPv4", "State:/Network/Interface/\(interface)/IPv4"] as CFArray
        SCDynamicStoreSetNotificationKeys(newStore, keys, nil)
        if let source = SCDynamicStoreCreateRunLoopSource(nil, newStore, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            storeSource = source
        }
        store = newStore
    }

    private func scheduleCheck(_ delay: TimeInterval = 0.6) {
        checkWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.checkNetwork() }
        checkWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func refreshSnapshotAsync() {
        queue.async {
            let iface = self.resolveInterface(for: self.config.serviceName)
            let snap = self.collectSnapshot(interface: iface)
            DispatchQueue.main.async {
                self.snapshot = snap
                self.setupNetworkMonitor(interface: iface)
                if self.isMenuOpen {
                    self.buildMenu()
                }
            }
        }
    }

    private func checkNetwork() {
        queue.async {
            let iface = self.resolveInterface(for: self.config.serviceName)
            let ip = self.currentIP(interface: iface)
            let match = self.config.isConfigured && ip.hasPrefix(self.config.hotspotPrefix)
            var on = self.proxyEnabled()
            let ipChanged = (ip != self.lastIP)
            if ipChanged {
                self.lastIP = ip
                self.suppressAuto = false
            }

            if self.config.autoMode && self.config.isConfigured && !self.suppressAuto {
                if match {
                    if !on {
                        if self.proxyOn() {
                            on = true
                        }
                    }
                    self.autoOpened = true
                } else if on && self.autoOpened {
                    _ = self.proxyOff()
                    on = false
                    self.autoOpened = false
                } else if !on {
                    self.autoOpened = false
                }
            }

            let snap = NetworkSnapshot(
                ip: ip,
                proxyEnabled: on,
                savedNetworks: self.savedNetworks(interface: iface),
                interfaceName: iface
            )
            DispatchQueue.main.async {
                self.snapshot = snap
                self.setupNetworkMonitor(interface: iface)
                self.buildMenu()
            }
        }
    }

    private func buildMenu() {
        menu.removeAllItems()

        let ip = snapshot.ip
        let onProxy = snapshot.proxyEnabled
        let match = config.isConfigured && ip.hasPrefix(config.hotspotPrefix)

        let statusTitle: String
        if !config.isConfigured {
            statusTitle = "尚未配置代理与网段前缀（请点下方「设置…」）"
        } else {
            statusTitle = "代理：\(onProxy ? "开" : "关")    IP（\(snapshot.interfaceName)）：\(ip)   \(match ? "✓ 热点" : "非热点")"
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if config.isConfigured {
            let targetLabel = config.hotspotSSID.isEmpty ? "\(config.hotspotPrefix)*" : config.hotspotSSID
            let summary = NSMenuItem(title: "\(config.proxyHost):\(config.proxyPort) → \(targetLabel)", action: nil, keyEquivalent: "")
            summary.isEnabled = false
            menu.addItem(summary)
        }
        menu.addItem(.separator())

        let auto = NSMenuItem(title: "自动检测：\(config.autoMode ? "开" : "关")", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self
        auto.state = config.autoMode ? .on : .off
        menu.addItem(auto)

        let onItem = NSMenuItem(title: "手动开代理", action: #selector(manualProxyOn), keyEquivalent: "")
        onItem.target = self
        onItem.isEnabled = !config.proxyHost.trimmingCharacters(in: .whitespaces).isEmpty
        menu.addItem(onItem)

        let offItem = NSMenuItem(title: "手动关代理", action: #selector(manualProxyOff), keyEquivalent: "")
        offItem.target = self
        menu.addItem(offItem)

        menu.addItem(.separator())

        let wifiItem = NSMenuItem(title: "切换 Wi-Fi", action: nil, keyEquivalent: "")
        let wifiMenu = NSMenu()
        for name in snapshot.savedNetworks {
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
        queue.async {
            self.autoOpened = false
            self.suppressAuto = false
            DispatchQueue.main.async {
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
                self.scheduleCheck(0.2)
            }
        }
    }

    @objc private func manualProxyOn() {
        queue.async {
            let ok = self.proxyOn()
            self.autoOpened = false
            self.suppressAuto = false
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
                if !ok {
                    self.showAlert("开启代理失败", "请检查「设置…」中的代理服务器和端口是否正确。")
                }
            }
        }
    }

    @objc private func manualProxyOff() {
        queue.async {
            _ = self.proxyOff()
            self.autoOpened = false
            self.suppressAuto = true
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
            }
        }
    }

    @objc private func joinNetwork(_ sender: NSMenuItem) {
        guard let ssid = sender.representedObject as? String else { return }
        let waitSec = config.waitSeconds
        queue.async {
            let iface = self.resolveInterface(for: self.config.serviceName)
            if self.config.autoReleaseOnSwitch { _ = self.proxyOff() }
            let res = self.run(self.ns, ["-setairportnetwork", iface, ssid], timeout: 10.0)
            let failed = res.status != 0 || res.output.contains("Failed") || res.output.lowercased().contains("error")
            let snap = self.collectSnapshot(interface: iface)
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
                if failed {
                    self.showAlert("自动切换失败", "系统不允许脚本直接切换 Wi-Fi。\n请点菜单栏的 Wi-Fi 图标手动选择「\(ssid)」，连上后会自动开代理。")
                } else {
                    // 非阻塞等待切网后复检，避免阻塞后台队列
                    self.scheduleCheck(TimeInterval(waitSec))
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
