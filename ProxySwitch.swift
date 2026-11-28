import Cocoa
import Darwin
import SystemConfiguration

// MARK: - 自动策略（互斥）

enum AutoStrategy: Int {
    case none = 0
    case phoneProxy = 1
    case localClash = 2
}

// MARK: - 配置

final class Config {
    static let shared = Config()
    private let d = UserDefaults.standard

    // MARK: 手机代理（热点转发到手机 Clash）
    var hotspotSSID: String { get { d.string(forKey: "hotspotSSID") ?? "" } set { d.set(newValue, forKey: "hotspotSSID") } }
    var proxyHost: String { get { d.string(forKey: "proxyHost") ?? "" } set { d.set(newValue, forKey: "proxyHost") } }
    var proxyPort: String { get { d.string(forKey: "proxyPort") ?? "7890" } set { d.set(newValue, forKey: "proxyPort") } }
    var serviceName: String { get { d.string(forKey: "serviceName") ?? "Wi-Fi" } set { d.set(newValue, forKey: "serviceName") } }
    var iconName: String { get { d.string(forKey: "iconName") ?? "key.fill" } set { d.set(newValue, forKey: "iconName") } }
    var syncPAC: Bool { get { d.object(forKey: "syncPAC") as? Bool ?? true } set { d.set(newValue, forKey: "syncPAC") } }
    var alsoSOCKS: Bool { get { d.object(forKey: "alsoSOCKS") as? Bool ?? false } set { d.set(newValue, forKey: "alsoSOCKS") } }
    var socksPort: String { get { d.string(forKey: "socksPort") ?? "7891" } set { d.set(newValue, forKey: "socksPort") } }
    var hotspotPrefix: String { get { d.string(forKey: "hotspotPrefix") ?? "" } set { d.set(newValue, forKey: "hotspotPrefix") } }

    var autoMode: Bool {
        get { d.object(forKey: "autoMode") as? Bool ?? true }
        set {
            d.set(newValue, forKey: "autoMode")
            if newValue { d.set(false, forKey: "clashAutoMode") }
        }
    }

    // MARK: 本机 Clash Verge 控制（仅指定网段开启）
    var clashAutoMode: Bool {
        get { d.object(forKey: "clashAutoMode") as? Bool ?? false }
        set {
            d.set(newValue, forKey: "clashAutoMode")
            if newValue { d.set(false, forKey: "autoMode") }
        }
    }

    var autoStrategy: AutoStrategy {
        get {
            if autoMode { return .phoneProxy }
            if clashAutoMode { return .localClash }
            return .none
        }
        set {
            switch newValue {
            case .none:
                d.set(false, forKey: "autoMode")
                d.set(false, forKey: "clashAutoMode")
            case .phoneProxy:
                d.set(true, forKey: "autoMode")
                d.set(false, forKey: "clashAutoMode")
            case .localClash:
                d.set(false, forKey: "autoMode")
                d.set(true, forKey: "clashAutoMode")
            }
        }
    }

    var clashWifiPrefixes: String { get { d.string(forKey: "clashWifiPrefixes") ?? "" } set { d.set(newValue, forKey: "clashWifiPrefixes") } }
    var clashControlTUN: Bool { get { d.object(forKey: "clashControlTUN") as? Bool ?? true } set { d.set(newValue, forKey: "clashControlTUN") } }
    var clashControlMode: Bool { get { d.object(forKey: "clashControlMode") as? Bool ?? true } set { d.set(newValue, forKey: "clashControlMode") } }
    var clashControlSysProxy: Bool { get { d.object(forKey: "clashControlSysProxy") as? Bool ?? false } set { d.set(newValue, forKey: "clashControlSysProxy") } }
    var clashSysProxyPort: String { get { d.string(forKey: "clashSysProxyPort") ?? "7897" } set { d.set(newValue, forKey: "clashSysProxyPort") } }
    var clashSocketPath: String {
        get {
            let saved = d.string(forKey: "clashSocketPath")?.trimmingCharacters(in: .whitespaces) ?? ""
            return saved.isEmpty ? Self.defaultClashSocketPath : saved
        }
        set { d.set(newValue, forKey: "clashSocketPath") }
    }

    static var defaultClashSocketPath: String {
        "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"
    }

    var isProxyConfigured: Bool {
        !proxyHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !Self.parsePrefixes(hotspotPrefix).isEmpty
    }

    var isClashConfigured: Bool {
        !Self.parsePrefixes(clashWifiPrefixes).isEmpty
    }

    static func parsePrefixes(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func ipMatchesPrefixes(_ ip: String, _ rawPrefixes: String) -> Bool {
        guard !ip.isEmpty, ip != "未连接" else { return false }
        return parsePrefixes(rawPrefixes).contains { ip.hasPrefix($0) }
    }

    static func isValidPort(_ raw: String) -> Bool {
        guard let port = Int(raw), (1...65535).contains(port) else { return false }
        return true
    }
}

// MARK: - 网络与 Clash 状态快照

private struct ClashStatus {
    var available: Bool = false
    var tunEnabled: Bool = false
    var mode: String = "rule"
}

private struct NetworkSnapshot {
    var ip: String = "检测中…"
    var proxyEnabled: Bool = false
    var proxyServer: String = ""
    var proxyPort: String = ""
    var interfaceName: String = "en0"
    var clash: ClashStatus = ClashStatus()

    var isLocalClashProxyActive: Bool {
        proxyEnabled && (proxyServer == "127.0.0.1" || proxyServer == "localhost")
    }

    var isPhoneProxyActive: Bool {
        proxyEnabled && !isLocalClashProxyActive
    }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let config = Config.shared
    private var onSave: (_ strategyChanged: Bool) -> Void

    // 互斥自动模式单选框
    private var autoNoneRadio: NSButton!
    private var autoPhoneRadio: NSButton!
    private var autoClashRadio: NSButton!

    // 手机代理控件
    private var ssidField: NSTextField!
    private var hostField: NSTextField!
    private var portField: NSTextField!
    private var serviceField: NSTextField!
    private var prefixField: NSTextField!
    private var socksPortField: NSTextField!
    private var syncPACCheck: NSButton!
    private var socksCheck: NSButton!

    // Clash 控件
    private var clashPrefixesField: NSTextField!
    private var clashSocketField: NSTextField!
    private var clashSysProxyPortField: NSTextField!
    private var clashTUNCheck: NSButton!
    private var clashModeCheck: NSButton!
    private var clashSysProxyCheck: NSButton!

    // 通用控件
    private var iconPopup: NSPopUpButton!

    private let iconChoices: [(String, String)] = [
        ("key.fill", "钥匙"), ("wifi", "Wi-Fi"), ("lock.fill", "锁"),
        ("shield.fill", "盾牌"), ("network", "网络"), ("globe", "地球"),
        ("antenna.radiowaves.left.and.right", "信号"), ("bolt.fill", "闪电")
    ]

    init(onSave: @escaping (_ strategyChanged: Bool) -> Void) {
        self.onSave = onSave
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 700),
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
        label.widthAnchor.constraint(equalToConstant: 155).isActive = true
        let h = NSStackView(views: [label, control])
        h.orientation = .horizontal
        h.spacing = 10
        h.alignment = .centerY
        return h
    }

    private func sectionTitle(_ text: String) -> NSView {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.boldSystemFont(ofSize: 13)
        return l
    }

    private func hint(_ text: String) -> NSView {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 490).isActive = true
        return box
    }

    @objc private func autoRadioChanged(_ sender: NSButton) {
        for btn in [autoNoneRadio!, autoPhoneRadio!, autoClashRadio!] {
            btn.state = (btn === sender) ? .on : .off
        }
    }

    private func buildUI() {
        autoNoneRadio = NSButton(radioButtonWithTitle: "关闭自动（仅通过菜单手动切换）", target: self, action: #selector(autoRadioChanged(_:)))
        autoPhoneRadio = NSButton(radioButtonWithTitle: "自动：手机代理（连上手机热点，转发流量到手机 Clash）", target: self, action: #selector(autoRadioChanged(_:)))
        autoClashRadio = NSButton(radioButtonWithTitle: "自动：本机 Clash（仅连上指定 Wi-Fi 时开启，离开关闭）", target: self, action: #selector(autoRadioChanged(_:)))

        ssidField = NSTextField(string: "")
        ssidField.placeholderString = "可选，仅用于菜单展示"
        hostField = NSTextField(string: "")
        hostField.placeholderString = "手机热点网关 IP，例：10.23.216.132"
        portField = NSTextField(string: "")
        portField.placeholderString = "1–65535（默认 7890）"
        serviceField = NSTextField(string: "")
        serviceField.placeholderString = "默认 Wi-Fi"
        prefixField = NSTextField(string: "")
        prefixField.placeholderString = "例：10.23.216.（多个用逗号分隔）"
        socksPortField = NSTextField(string: "")
        socksPortField.placeholderString = "1–65535（默认 7891）"

        clashPrefixesField = NSTextField(string: "")
        clashPrefixesField.placeholderString = "例：192.168.1., 192.168.31."
        clashSocketField = NSTextField(string: "")
        clashSocketField.placeholderString = Config.defaultClashSocketPath
        clashSysProxyPortField = NSTextField(string: "")
        clashSysProxyPortField.placeholderString = "默认 7897"

        for f in [ssidField, hostField, portField, serviceField, prefixField, socksPortField,
                  clashPrefixesField, clashSocketField, clashSysProxyPortField] {
            f!.widthAnchor.constraint(equalToConstant: 265).isActive = true
        }

        iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (symbol, title) in iconChoices {
            iconPopup.addItem(withTitle: title)
            iconPopup.lastItem?.representedObject = symbol
        }

        syncPACCheck = NSButton(checkboxWithTitle: "开启代理时关闭「自动配置代理」(PAC)", target: nil, action: nil)
        socksCheck = NSButton(checkboxWithTitle: "同时设置手机代理的 SOCKS 端口", target: nil, action: nil)

        clashTUNCheck = NSButton(checkboxWithTitle: "控制 TUN 模式（连上开启 / 离开关闭）", target: nil, action: nil)
        clashModeCheck = NSButton(checkboxWithTitle: "控制出站模式（连上 rule / 离开 direct）", target: nil, action: nil)
        clashSysProxyCheck = NSButton(checkboxWithTitle: "同时控制本机 Clash 系统代理（127.0.0.1:端口）", target: nil, action: nil)

        let save = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [
            sectionTitle("一、自动模式（两者互斥，只能启用一种）"),
            autoNoneRadio,
            autoPhoneRadio,
            autoClashRadio,

            separator(),
            sectionTitle("二、手机代理（手机开 Clash 并允许局域网连接，将流量转过去）"),
            row("手机热点网段前缀", prefixField),
            hint("  用本机 IP 前缀判断，支持逗号分隔多个（例：10.23.216.）"),
            row("手机代理 IP", hostField),
            row("HTTP/HTTPS 端口", portField),
            row("SOCKS 端口", socksPortField),
            row("热点名称（展示用）", ssidField),
            syncPACCheck,
            socksCheck,

            separator(),
            sectionTitle("三、本机 Clash Verge 控制（仅连上指定网段开启）"),
            row("Clash 启用网段前缀", clashPrefixesField),
            hint("  只有连上这些网段才开启本机 Clash；校园网等其他网络自动关闭"),
            row("本机 Clash 端口", clashSysProxyPortField),
            row("Clash Socket 路径", clashSocketField),
            clashTUNCheck,
            clashModeCheck,
            clashSysProxyCheck,

            separator(),
            row("网络服务名", serviceField),
            row("菜单栏图标", iconPopup),
            buttons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])
        window?.contentView = content

        let fit = stack.fittingSize
        window?.setContentSize(NSSize(width: max(550, fit.width + 42), height: max(420, fit.height + 36)))
    }

    private func loadValues() {
        let strategy = config.autoStrategy
        autoNoneRadio.state = (strategy == .none) ? .on : .off
        autoPhoneRadio.state = (strategy == .phoneProxy) ? .on : .off
        autoClashRadio.state = (strategy == .localClash) ? .on : .off

        ssidField.stringValue = config.hotspotSSID
        hostField.stringValue = config.proxyHost
        portField.stringValue = config.proxyPort
        serviceField.stringValue = config.serviceName
        prefixField.stringValue = config.hotspotPrefix
        socksPortField.stringValue = config.socksPort
        syncPACCheck.state = config.syncPAC ? .on : .off
        socksCheck.state = config.alsoSOCKS ? .on : .off

        clashPrefixesField.stringValue = config.clashWifiPrefixes
        clashSocketField.stringValue = config.clashSocketPath
        clashSysProxyPortField.stringValue = config.clashSysProxyPort
        clashTUNCheck.state = config.clashControlTUN ? .on : .off
        clashModeCheck.state = config.clashControlMode ? .on : .off
        clashSysProxyCheck.state = config.clashControlSysProxy ? .on : .off

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
            showValidationError("手机代理 HTTP/HTTPS 端口必须是 1–65535 之间的整数。")
            return
        }
        let socksPort = socksPortField.stringValue.trimmingCharacters(in: .whitespaces)
        if socksCheck.state == .on && !Config.isValidPort(socksPort) {
            showValidationError("手机代理 SOCKS 端口必须是 1–65535 之间的整数。")
            return
        }
        let clashPort = clashSysProxyPortField.stringValue.trimmingCharacters(in: .whitespaces)
        if clashSysProxyCheck.state == .on && !Config.isValidPort(clashPort) {
            showValidationError("本机 Clash 端口必须是 1–65535 之间的整数。")
            return
        }

        let newPrefixes = clashPrefixesField.stringValue.trimmingCharacters(in: .whitespaces)
        if autoClashRadio.state == .on && Config.parsePrefixes(newPrefixes).isEmpty {
            showValidationError("选择「自动：本机 Clash」时，请先填写 Clash 启用网段前缀。")
            return
        }

        let newHost = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        let newPhonePrefix = prefixField.stringValue.trimmingCharacters(in: .whitespaces)
        if autoPhoneRadio.state == .on && (newHost.isEmpty || Config.parsePrefixes(newPhonePrefix).isEmpty) {
            showValidationError("选择「自动：手机代理」时，请先填写手机热点网段前缀与手机代理 IP。")
            return
        }

        let previousStrategy = config.autoStrategy
        let newStrategy: AutoStrategy
        if autoPhoneRadio.state == .on {
            newStrategy = .phoneProxy
        } else if autoClashRadio.state == .on {
            newStrategy = .localClash
        } else {
            newStrategy = .none
        }
        config.autoStrategy = newStrategy

        let service = serviceField.stringValue.trimmingCharacters(in: .whitespaces)
        config.hotspotSSID = ssidField.stringValue.trimmingCharacters(in: .whitespaces)
        config.proxyHost = newHost
        config.proxyPort = port
        config.serviceName = service.isEmpty ? "Wi-Fi" : service
        config.hotspotPrefix = newPhonePrefix
        if Config.isValidPort(socksPort) {
            config.socksPort = socksPort
        }
        config.syncPAC = syncPACCheck.state == .on
        config.alsoSOCKS = socksCheck.state == .on

        config.clashWifiPrefixes = newPrefixes
        config.clashSocketPath = clashSocketField.stringValue.trimmingCharacters(in: .whitespaces)
        if Config.isValidPort(clashPort) {
            config.clashSysProxyPort = clashPort
        }
        config.clashControlTUN = clashTUNCheck.state == .on
        config.clashControlMode = clashModeCheck.state == .on
        config.clashControlSysProxy = clashSysProxyCheck.state == .on

        if let sym = iconPopup.selectedItem?.representedObject as? String {
            config.iconName = sym
        }

        onSave(newStrategy != previousStrategy)
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
    private let curl = "/usr/bin/curl"
    private var settingsController: SettingsWindowController?

    // 所有可变网络状态仅在 queue 上读写；snapshot 通过主线程更新菜单
    private let queue = DispatchQueue(label: "com.dsh.proxyswitch.monitor")
    private var autoOpened = false
    private var suppressAuto = false
    private var clashSuppressAuto = false
    private var lastIP = ""
    private var snapshot = NetworkSnapshot()
    private var monitoredInterface = ""

    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?
    private var checkWorkItem: DispatchWorkItem?
    private var isMenuOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 防止历史配置同时打开两个自动模式
        if config.autoMode && config.clashAutoMode {
            config.autoStrategy = .phoneProxy
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyIcon()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        buildMenu()

        queue.async {
            let iface = self.resolveInterface(for: self.config.serviceName)
            let ip = self.currentIP(interface: iface)
            let web = self.currentWebProxy()
            if self.config.autoStrategy == .phoneProxy,
               self.config.isProxyConfigured,
               !Config.ipMatchesPrefixes(ip, self.config.hotspotPrefix),
               web.server == self.config.proxyHost {
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
        let sem = DispatchSemaphore(value: 0)
        var freshSnap: NetworkSnapshot?
        queue.async {
            let iface = self.resolveInterface(for: self.config.serviceName)
            freshSnap = self.collectSnapshot(interface: iface)
            sem.signal()
        }
        if sem.wait(timeout: .now() + 0.35) == .success, let snap = freshSnap {
            snapshot = snap
        } else {
            refreshSnapshotAsync()
        }
        buildMenu()
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

    private func currentWebProxy() -> (enabled: Bool, server: String, port: String) {
        let out = run(ns, ["-getwebproxy", config.serviceName]).output
        var enabled = false
        var server = ""
        var port = ""
        for line in out.split(separator: "\n") {
            if line.hasPrefix("Enabled:") {
                enabled = line.contains("Yes")
            } else if line.hasPrefix("Server:") {
                server = line.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Port:") {
                port = line.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (enabled, server, port)
    }

    private func currentIP(interface: String) -> String {
        let res = run(ipconfig, ["getifaddr", interface])
        let out = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (res.status == 0 && !out.isEmpty) ? out : "未连接"
    }

    // MARK: Clash Verge（Mihomo Unix Socket）控制

    private func queryClashStatus() -> ClashStatus {
        let sock = config.clashSocketPath
        guard FileManager.default.fileExists(atPath: sock) else { return ClashStatus() }

        let res = run(curl, ["-s", "--max-time", "2", "--unix-socket", sock, "http://localhost/configs"], timeout: 3.0)
        guard res.status == 0,
              let data = res.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ClashStatus()
        }

        let tunDict = json["tun"] as? [String: Any]
        let tunEnabled = (tunDict?["enable"] as? Bool) ?? false
        let mode = (json["mode"] as? String) ?? "rule"
        return ClashStatus(available: true, tunEnabled: tunEnabled, mode: mode)
    }

    @discardableResult
    private func patchClashConfig(_ payload: [String: Any]) -> Bool {
        let sock = config.clashSocketPath
        guard FileManager.default.fileExists(atPath: sock),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let body = String(data: data, encoding: .utf8) else {
            return false
        }

        let res = run(curl, [
            "-s", "-f", "--max-time", "2",
            "--unix-socket", sock,
            "-X", "PATCH",
            "-H", "Content-Type: application/json",
            "-d", body,
            "http://localhost/configs"
        ], timeout: 3.0)
        return res.status == 0
    }

    @discardableResult
    private func setClashActive(_ active: Bool) -> Bool {
        var patch: [String: Any] = [:]
        if config.clashControlTUN {
            patch["tun"] = ["enable": active]
        }
        if config.clashControlMode {
            patch["mode"] = active ? "rule" : "direct"
        }

        var ok = true
        if !patch.isEmpty {
            ok = patchClashConfig(patch)
        }

        if config.clashControlSysProxy {
            if active {
                _ = setSystemProxy(host: "127.0.0.1", port: config.clashSysProxyPort, socksPort: config.clashSysProxyPort, enableSocks: true)
            } else {
                let web = currentWebProxy()
                if web.enabled && (web.server == "127.0.0.1" || web.server == "localhost") {
                    _ = proxyOff()
                }
            }
        }
        return ok
    }

    private func collectSnapshot(interface: String) -> NetworkSnapshot {
        let web = currentWebProxy()
        return NetworkSnapshot(
            ip: currentIP(interface: interface),
            proxyEnabled: web.enabled,
            proxyServer: web.server,
            proxyPort: web.port,
            interfaceName: interface,
            clash: queryClashStatus()
        )
    }

    @discardableResult
    private func setSystemProxy(host: String, port: String, socksPort: String, enableSocks: Bool) -> Bool {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, Config.isValidPort(port) else { return false }
        if config.syncPAC {
            _ = run(ns, ["-setautoproxystate", config.serviceName, "off"])
        }
        let r1 = run(ns, ["-setwebproxy", config.serviceName, h, port])
        let r2 = run(ns, ["-setsecurewebproxy", config.serviceName, h, port])
        if enableSocks && Config.isValidPort(socksPort) {
            _ = run(ns, ["-setsocksfirewallproxy", config.serviceName, h, socksPort])
        }
        return r1.status == 0 && r2.status == 0
    }

    @discardableResult
    private func phoneProxyOn() -> Bool {
        setSystemProxy(host: config.proxyHost, port: config.proxyPort, socksPort: config.socksPort, enableSocks: config.alsoSOCKS)
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
            let matchPhone = self.config.isProxyConfigured && Config.ipMatchesPrefixes(ip, self.config.hotspotPrefix)
            let matchClash = self.config.isClashConfigured && Config.ipMatchesPrefixes(ip, self.config.clashWifiPrefixes)

            var web = self.currentWebProxy()
            let ipChanged = (ip != self.lastIP)
            if ipChanged {
                self.lastIP = ip
                self.suppressAuto = false
                self.clashSuppressAuto = false
            }

            let strategy = self.config.autoStrategy
            var clash = self.queryClashStatus()

            switch strategy {
            case .none:
                break

            case .phoneProxy:
                if self.config.isProxyConfigured && !self.suppressAuto {
                    if matchPhone {
                        if !web.enabled || web.server != self.config.proxyHost || web.port != self.config.proxyPort {
                            _ = self.phoneProxyOn()
                            web = self.currentWebProxy()
                        }
                        self.autoOpened = true
                    } else if web.enabled && self.autoOpened {
                        _ = self.proxyOff()
                        web = self.currentWebProxy()
                        self.autoOpened = false
                    } else if !web.enabled {
                        self.autoOpened = false
                    }
                }

            case .localClash:
                if self.config.isClashConfigured && clash.available && !self.clashSuppressAuto {
                    if matchClash {
                        let needTUN = self.config.clashControlTUN && !clash.tunEnabled
                        let needMode = self.config.clashControlMode && clash.mode != "rule"
                        let needSys = self.config.clashControlSysProxy &&
                            (!web.enabled || (web.server != "127.0.0.1" && web.server != "localhost") || web.port != self.config.clashSysProxyPort)

                        if needTUN || needMode || needSys {
                            _ = self.setClashActive(true)
                            clash = self.queryClashStatus()
                            web = self.currentWebProxy()
                        }
                    } else {
                        let needCloseTUN = self.config.clashControlTUN && clash.tunEnabled
                        let needDirect = self.config.clashControlMode && clash.mode != "direct"
                        let needCloseSys = self.config.clashControlSysProxy &&
                            web.enabled && (web.server == "127.0.0.1" || web.server == "localhost")

                        if needCloseTUN || needDirect || needCloseSys {
                            _ = self.setClashActive(false)
                            clash = self.queryClashStatus()
                            web = self.currentWebProxy()
                        }
                    }
                }
            }

            let snap = NetworkSnapshot(
                ip: ip,
                proxyEnabled: web.enabled,
                proxyServer: web.server,
                proxyPort: web.port,
                interfaceName: iface,
                clash: clash
            )
            DispatchQueue.main.async {
                self.snapshot = snap
                self.setupNetworkMonitor(interface: iface)
                self.buildMenu()
            }
        }
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "rule": return "规则 (rule)"
        case "direct": return "直连 (direct)"
        case "global": return "全局 (global)"
        default: return mode
        }
    }

    private func disabledHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func buildMenu() {
        menu.removeAllItems()

        let ip = snapshot.ip
        let matchPhone = config.isProxyConfigured && Config.ipMatchesPrefixes(ip, config.hotspotPrefix)
        let matchClash = config.isClashConfigured && Config.ipMatchesPrefixes(ip, config.clashWifiPrefixes)

        // 1. 顶部实时状态
        let netTag = matchPhone ? "✓ 手机热点网段" : (matchClash ? "✓ Clash 指定网段" : "其他网络")
        menu.addItem(disabledHeader("IP（\(snapshot.interfaceName)）：\(ip)   \(netTag)"))

        if snapshot.isPhoneProxyActive {
            menu.addItem(disabledHeader("手机代理：开（\(snapshot.proxyServer):\(snapshot.proxyPort)）"))
        } else {
            menu.addItem(disabledHeader("手机代理：关"))
        }

        if snapshot.clash.available {
            let localSys = snapshot.isLocalClashProxyActive ? "开" : "关"
            menu.addItem(disabledHeader("本机 Clash：TUN \(snapshot.clash.tunEnabled ? "开" : "关") · 本地代理 \(localSys) · \(modeLabel(snapshot.clash.mode))"))
        } else {
            menu.addItem(disabledHeader("本机 Clash：未运行或 Socket 不可达"))
        }

        menu.addItem(.separator())

        // 2. 自动模式（互斥单选）
        menu.addItem(disabledHeader("自动模式（互斥）"))
        let strategy = config.autoStrategy

        let autoOffItem = NSMenuItem(title: "关闭自动（仅手动）", action: #selector(selectAutoNone), keyEquivalent: "")
        autoOffItem.target = self
        autoOffItem.state = (strategy == .none) ? .on : .off
        menu.addItem(autoOffItem)

        let autoPhoneTitle = config.isProxyConfigured
            ? "自动：手机代理（连热点转手机 Clash）"
            : "自动：手机代理（需先配置热点 IP）"
        let autoPhoneItem = NSMenuItem(title: autoPhoneTitle, action: #selector(selectAutoPhone), keyEquivalent: "")
        autoPhoneItem.target = self
        autoPhoneItem.state = (strategy == .phoneProxy) ? .on : .off
        autoPhoneItem.isEnabled = config.isProxyConfigured
        menu.addItem(autoPhoneItem)

        let autoClashTitle = config.isClashConfigured
            ? "自动：本机 Clash（仅连指定 Wi-Fi 开启）"
            : "自动：本机 Clash（需先配置启用网段）"
        let autoClashItem = NSMenuItem(title: autoClashTitle, action: #selector(selectAutoClash), keyEquivalent: "")
        autoClashItem.target = self
        autoClashItem.state = (strategy == .localClash) ? .on : .off
        autoClashItem.isEnabled = config.isClashConfigured
        menu.addItem(autoClashItem)

        menu.addItem(.separator())

        // 3. 手机代理（热点转发）手动操作
        let phoneTarget = config.proxyHost.isEmpty ? "未配置" : "\(config.proxyHost):\(config.proxyPort)"
        menu.addItem(disabledHeader("手机代理（热点转发 → \(phoneTarget)）"))

        let phoneOnItem = NSMenuItem(title: "开启手机代理", action: #selector(manualPhoneProxyOn), keyEquivalent: "")
        phoneOnItem.target = self
        phoneOnItem.state = snapshot.isPhoneProxyActive ? .on : .off
        phoneOnItem.isEnabled = !config.proxyHost.trimmingCharacters(in: .whitespaces).isEmpty
        menu.addItem(phoneOnItem)

        let phoneOffItem = NSMenuItem(title: "关闭手机代理", action: #selector(manualPhoneProxyOff), keyEquivalent: "")
        phoneOffItem.target = self
        menu.addItem(phoneOffItem)

        menu.addItem(.separator())

        // 4. 本机 Clash Verge 控制（增加多项快捷操作）
        menu.addItem(disabledHeader("本机 Clash 控制"))

        let clashOnItem = NSMenuItem(title: "一键开启本机 Clash（TUN + 规则）", action: #selector(manualClashOn), keyEquivalent: "")
        clashOnItem.target = self
        clashOnItem.isEnabled = snapshot.clash.available
        menu.addItem(clashOnItem)

        let clashOffItem = NSMenuItem(title: "一键关闭本机 Clash（关 TUN + 直连）", action: #selector(manualClashOff), keyEquivalent: "")
        clashOffItem.target = self
        clashOffItem.isEnabled = snapshot.clash.available
        menu.addItem(clashOffItem)

        let tunItem = NSMenuItem(title: "TUN 模式", action: #selector(toggleClashTUN), keyEquivalent: "")
        tunItem.target = self
        tunItem.state = snapshot.clash.tunEnabled ? .on : .off
        tunItem.isEnabled = snapshot.clash.available
        menu.addItem(tunItem)

        let localSysProxyItem = NSMenuItem(title: "本地系统代理（127.0.0.1:\(config.clashSysProxyPort)）", action: #selector(toggleLocalClashSysProxy), keyEquivalent: "")
        localSysProxyItem.target = self
        localSysProxyItem.state = snapshot.isLocalClashProxyActive ? .on : .off
        menu.addItem(localSysProxyItem)

        let modeMenuItem = NSMenuItem(title: "出站模式", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        for (val, label) in [("rule", "规则 (rule)"), ("direct", "直连 (direct)"), ("global", "全局 (global)")] {
            let item = NSMenuItem(title: label, action: #selector(selectClashMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            item.state = (snapshot.clash.available && snapshot.clash.mode == val) ? .on : .off
            item.isEnabled = snapshot.clash.available
            modeSubmenu.addItem(item)
        }
        modeMenuItem.submenu = modeSubmenu
        modeMenuItem.isEnabled = snapshot.clash.available
        menu.addItem(modeMenuItem)

        let openClashItem = NSMenuItem(title: "打开 Clash Verge…", action: #selector(openClashVergeApp), keyEquivalent: "")
        openClashItem.target = self
        menu.addItem(openClashItem)

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

    // MARK: Actions

    private func deactivateUnselected(for strategy: AutoStrategy) {
        switch strategy {
        case .phoneProxy:
            // 切到自动手机代理：关闭未选中的本机 Clash（关 TUN + 切直连 + 清掉 127.0.0.1 本地系统代理）
            _ = patchClashConfig(["tun": ["enable": false], "mode": "direct"])
            let web = currentWebProxy()
            if web.enabled && (web.server == "127.0.0.1" || web.server == "localhost") {
                _ = proxyOff()
            }
        case .localClash:
            // 切到自动本机 Clash：关掉未选中的手机代理（非 127.0.0.1 的系统代理）
            let web = currentWebProxy()
            if web.enabled && web.server != "127.0.0.1" && web.server != "localhost" {
                _ = proxyOff()
            }
        case .none:
            break
        }
    }

    private func applyStrategy(_ strategy: AutoStrategy) {
        config.autoStrategy = strategy
        queue.async {
            self.autoOpened = false
            self.suppressAuto = false
            self.clashSuppressAuto = false
            self.deactivateUnselected(for: strategy)
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
                self.scheduleCheck(0.2)
            }
        }
    }

    @objc private func selectAutoNone() { applyStrategy(.none) }
    @objc private func selectAutoPhone() { applyStrategy(.phoneProxy) }
    @objc private func selectAutoClash() { applyStrategy(.localClash) }

    @objc private func manualPhoneProxyOn() {
        queue.async {
            let ok = self.phoneProxyOn()
            self.autoOpened = false
            self.suppressAuto = false
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
                self.settingsController?.refreshFromConfig()
                if !ok {
                    self.showAlert("开启手机代理失败", "请检查「设置…」中的手机代理 IP 和端口是否正确。")
                }
            }
        }
    }

    @objc private func manualPhoneProxyOff() {
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

    @objc private func manualClashOn() {
        queue.async {
            _ = self.setClashActive(true)
            self.clashSuppressAuto = true
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
            }
        }
    }

    @objc private func manualClashOff() {
        queue.async {
            _ = self.setClashActive(false)
            self.clashSuppressAuto = true
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
            }
        }
    }

    @objc private func toggleClashTUN() {
        queue.async {
            let cur = self.queryClashStatus()
            guard cur.available else { return }
            _ = self.patchClashConfig(["tun": ["enable": !cur.tunEnabled]])
            self.clashSuppressAuto = true
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
            }
        }
    }

    @objc private func toggleLocalClashSysProxy() {
        queue.async {
            let web = self.currentWebProxy()
            let isLocal = web.enabled && (web.server == "127.0.0.1" || web.server == "localhost")
            if isLocal {
                _ = self.proxyOff()
            } else {
                _ = self.setSystemProxy(host: "127.0.0.1", port: self.config.clashSysProxyPort, socksPort: self.config.clashSysProxyPort, enableSocks: true)
            }
            self.clashSuppressAuto = true
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
            }
        }
    }

    @objc private func selectClashMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        queue.async {
            _ = self.patchClashConfig(["mode": mode])
            self.clashSuppressAuto = true
            let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.buildMenu()
            }
        }
    }

    @objc private func openClashVergeApp() {
        let appURL = URL(fileURLWithPath: "/Applications/Clash Verge.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            showAlert("未找到 Clash Verge", "未在 /Applications/Clash Verge.app 找到 Clash Verge 客户端。")
        }
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController { [weak self] strategyChanged in
                guard let self = self else { return }
                self.applyIcon()
                self.queue.async {
                    self.autoOpened = false
                    self.suppressAuto = false
                    self.clashSuppressAuto = false
                    if strategyChanged {
                        self.deactivateUnselected(for: self.config.autoStrategy)
                    }
                    let snap = self.collectSnapshot(interface: self.resolveInterface(for: self.config.serviceName))
                    DispatchQueue.main.async {
                        self.snapshot = snap
                        self.buildMenu()
                        self.scheduleCheck(0.2)
                    }
                }
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
