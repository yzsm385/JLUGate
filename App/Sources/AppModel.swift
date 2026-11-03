import Foundation
import Observation
import SwiftUI
import JLUGateCore
import JLUGateNet

/// UI 的唯一状态源。
///
/// 现在统一走 `AuthCoordinator`：UI 不再关心是 Dr.Com 还是有线/无线/网页认证，
/// 只订阅"协调器事件"（状态 / 链路 / 遥测 / 提示）。
@MainActor
@Observable
final class AppModel {
    var config: AppConfig
    var password: String
    var state: AuthState = .idle
    var link: AccessLink?
    var lastError: DrcomError?
    var clientIP: String?
    var sessionNumber: UInt16?
    var secondsOnline: UInt32 = 0
    var trafficStats: [UInt32] = []
    var recentLog: [String] = []
    var interfaces: [InterfaceSnapshot] = []
    var routeSummary: String = "未检测"
    var routeGuarantee: RouteGuarantee?
    var showWizard = false

    @ObservationIgnored private var coordinator: AuthCoordinator?
    @ObservationIgnored private var coordinatorTask: Task<Void, Never>?
    @ObservationIgnored private let portalBrowser = WKPortalBrowser()
    @ObservationIgnored private let interfacesProvider = SystemInterfaceProvider()
    @ObservationIgnored private var wizardWindow: NSWindow?
    @ObservationIgnored private let activityKeeper = ActivityKeeper()
    @ObservationIgnored private let pathMonitor = PathMonitor()
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var pathDebounce: Task<Void, Never>?

    init() {
        let loaded = ConfigStore.load()
        config = loaded
        password = CredentialStore.password(for: loaded.account) ?? ""
        showWizard = loaded.currentProfile?.configuredAt == nil
        refreshDiagnostics()
        observeSleepWake()
        observeNetworkPaths()
        if showWizard {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.presentWizard()
            }
        }
        Notifier.requestAuthorizationIfNeeded()
    }

    /// 首次启动 / 换账号时的向导窗口（PLAN §9.1）。
    func presentWizard() {
        if let wizardWindow {
            wizardWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: WizardView().environment(self))
        let window = NSWindow(contentViewController: controller)
        window.title = "JLU Gate · 初始设置"
        window.setContentSize(NSSize(width: 520, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable]
        wizardWindow = window
        showWizard = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 派生显示

    var statusColor: Color {
        switch state {
        case .online: .green
        case .failed: .red
        case .idle: .secondary
        default: .orange
        }
    }

    var statusSymbol: String {
        switch state {
        case .online: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "circle.dashed"
        case .reconnecting: "arrow.triangle.2.circlepath"
        default: "circle.dotted"
        }
    }

    var statusTitle: String {
        switch state {
        case .idle: "未登录"
        case .discovering: "正在识别网络…"
        case .challenging: "握手中…"
        case .authenticating: "认证中…"
        case .online: "在线"
        case .reconnecting(let attempt): "重连中（第 \(attempt) 次）"
        case .failed: "未连接"
        }
    }

    var linkTitle: String {
        link?.displayName ?? (config.link == "auto" ? "自动（未探测）" : config.link)
    }

    var detailLine: String {
        if case .failed(let error) = state { return error.userMessage }
        if let clientIP { return "本机 \(clientIP)" }
        return "\(config.server):\(config.serverPort)"
    }

    var isConfigured: Bool {
        config.currentProfile?.configuredAt != nil
    }

    var canOpenPortalLogin: Bool {
        link == .jluWiFi || config.link == "jluWiFi"
    }

    // MARK: 动作

    func connect() {
        guard !config.account.isEmpty, !password.isEmpty else {
            state = .failed(.malformed("还没填账号或密码"))
            return
        }
        guard IPv4Address(config.server) != nil else {
            state = .failed(.malformed("服务器地址不合法"))
            return
        }
        try? CredentialStore.save(password: password, account: config.account)
        ConfigStore.save(config)

        let profile = config.currentProfile
        let server = IPv4Address(config.server)!
        let engineConfiguration = EngineConfiguration(
            account: config.account,
            password: password,
            hostname: SystemHostname.value,
            registeredMAC: profile?.registeredMAC.flatMap(MACAddress.init),
            interfaceLock: config.interfaceLock,
            expectedIP: profile?.ip.flatMap(IPv4Address.init),
            expectedMask: profile?.mask,
            server: server,
            serverPort: UInt16(config.serverPort),
            localPort: UInt16(config.localPort),
            keepAliveInterval: .seconds(config.keepAlive.interval),
            missTolerance: config.keepAlive.missTolerance)

        let channelFactory: any ChannelFactory = config.channel == "bsd"
            ? BSDChannelFactory()
            : NWChannelFactory()
        let backoff = Backoff(base: config.backoff.base, cap: config.backoff.cap,
                              jitter: config.backoff.jitter, maxAttempts: config.backoff.maxAttempts)
        let portalConfiguration = PortalConfiguration(
            silentRetryOnce: config.portal.silentRetryOnce,
            promptCooldown: .seconds(Double(config.portal.promptCooldownSeconds)),
            probeInterval: .seconds(config.probe.interval),
            failTolerance: config.probe.failTolerance,
            dnsServers: (profile?.dns ?? []).compactMap(IPv4Address.init),
            backoff: backoff)
        let portalEntry = config.portal.entryURL.flatMap(URL.init(string:))
        let browser = portalBrowser

        let factory: @Sendable (AccessLink, InterfaceSnapshot) -> any AuthProvider = { link, _ in
            if link.usesDrcomUDP {
                let engine = DrcomEngine(configuration: engineConfiguration,
                                         codec: DrcomCodec(),
                                         channelFactory: channelFactory,
                                         interfaces: SystemInterfaceProvider(),
                                         clock: SystemClock(),
                                         backoff: backoff)
                return DrcomAuthProvider(engine: engine, link: link)
            }
            return PortalEngine(probe: ConnectivityProbe(),
                                browser: browser,
                                detector: PortalDetector(configuredURL: portalEntry),
                                configuration: portalConfiguration)
        }

        let coordinatorConfiguration = AuthCoordinator.Configuration(
            preference: LinkPreference(rawValue: config.link) ?? .auto,
            autoDetect: config.autoDetect,
            server: IPv4Endpoint(host: server, port: UInt16(config.serverPort)),
            localPort: UInt16(config.localPort),
            registeredMAC: profile?.registeredMAC.flatMap(MACAddress.init),
            interfaceLock: config.interfaceLock,
            dnsServers: (profile?.dns ?? []).compactMap(IPv4Address.init),
            probeTimeout: .seconds(config.probe.timeout))

        let coordinator = AuthCoordinator(configuration: coordinatorConfiguration,
                                          interfaces: interfacesProvider,
                                          detector: DefaultLinkDetector(),
                                          makeProvider: factory)
        self.coordinator = coordinator
        coordinatorTask?.cancel()
        coordinatorTask = Task { [weak self] in
            guard let self else { return }
            let events = await coordinator.events()
            await coordinator.start()
            for await event in events {
                await self.handle(event)
            }
        }
    }

    func disconnect() {
        activityKeeper.end()
        coordinatorTask?.cancel()
        coordinatorTask = nil
        let coordinator = self.coordinator
        self.coordinator = nil
        state = .idle
        clientIP = nil
        link = nil
        Task { await coordinator?.stop() }
    }

    func retry() {
        disconnect()
        connect()
    }

    /// 菜单里的"打开 Portal 登录页"。
    func openPortalLogin() {
        guard let coordinator else {
            recentLog.insert("还没开始认证：先点“登录”", at: 0)
            return
        }
        Task { await coordinator.requestPortalLogin() }
    }

    func saveProfile(_ profile: AppConfig.NetworkProfile) {
        var updated = profile
        if updated.configuredAt == nil {
            updated.configuredAt = ISO8601DateFormatter().string(from: .now)
        }
        config.currentProfile = updated
        ConfigStore.save(config)
        refreshDiagnostics()
    }

    func persist() {
        ConfigStore.save(config)
    }

    /// 从剪贴板里的参数卡还原配置（换机/重装用）。
    @discardableResult
    func importConfigCardFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            recentLog.insert("剪贴板里没有文本", at: 0)
            return false
        }
        let parsed = NetworkCard.parse(text)
        guard let account = parsed.account, !account.isEmpty else {
            recentLog.insert("这段文本里没有“账号:”行，无法还原", at: 0)
            return false
        }
        if let issues = validationIssues(parsed: parsed), !issues.isEmpty {
            recentLog.insert("参数卡校验失败：\(issues.first?.message ?? "")", at: 0)
            return false
        }

        config.account = account
        if let link = parsed.link, LinkPreference(rawValue: link) != nil {
            config.link = link
        }
        if let server = parsed.server { config.server = server }
        if let port = parsed.serverPort { config.serverPort = port }
        config.accounts[account] = AppConfig.NetworkProfile(
            ip: parsed.ip, mask: parsed.mask, gateway: parsed.gateway,
            dns: parsed.dns, registeredMAC: parsed.mac,
            interfaceHint: config.accounts[account]?.interfaceHint,
            configuredAt: config.accounts[account]?.configuredAt
                ?? ISO8601DateFormatter().string(from: .now))
        persist()
        refreshDiagnostics()
        showWizard = false
        recentLog.insert("已从参数卡还原账号 \(account) 的网络参数", at: 0)
        FileLogger.shared.log("导入参数卡：\(account)")
        return true
    }

    private func validationIssues(parsed: NetworkCard.Parsed) -> [NetworkValidation.Issue]? {
        NetworkValidation.issues(ip: parsed.ip, mask: parsed.mask,
                                 gateway: parsed.gateway, mac: parsed.mac)
    }

    /// 网络参数卡片：文本进剪贴板，二维码另存为 PNG。
    func exportConfigCard() {
        guard let profile = config.currentProfile else {
            recentLog.insert("还没有网络参数可导出：先完成向导", at: 0)
            return
        }
        let text = ConfigCard.text(config: config, profile: profile)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if let image = ConfigCard.qrImage(for: text),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("JLU-Gate-网络参数卡.png")
            try? png.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        recentLog.insert("已导出网络参数卡（文本在剪贴板，二维码已保存）", at: 0)
        FileLogger.shared.log("导出网络参数卡：账号 \(config.account)")
    }

    func finishWizard() {
        showWizard = false
        refreshDiagnostics()
    }

    // MARK: 诊断

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
        recentLog.insert("已复制诊断信息到剪贴板", at: 0)
    }

    func exportDiagnostics() {
        let text = diagnosticsText()
        let name = "JLU Gate 诊断 \(ISO8601DateFormatter().string(from: .now)).txt"
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            recentLog.insert("导出诊断失败：\(error.localizedDescription)", at: 0)
        }
    }

    private func diagnosticsText() -> String {
        var text = DiagnosticsReport.make(config: config, engineState: state,
                                          interfaces: interfaces)
        if let routeGuarantee {
            text += "\n\n== 路由保障 ==\n\(routeGuarantee)"
        }
        if !recentLog.isEmpty {
            text += "\n\n== 最近事件 ==\n" + recentLog.prefix(20).joined(separator: "\n")
        }
        return text
    }

    func refreshDiagnostics() {
        interfaces = interfacesProvider.physicalInterfaces()
        guard let server = IPv4Address(config.server) else {
            routeSummary = "服务器地址不合法"
            routeGuarantee = .noRoute
            return
        }
        let route = interfacesProvider.route(to: server)
        if let route {
            routeSummary = "\(config.server) → \(route.interface ?? "?")（网关 \(route.gateway ?? "-")）"
                + (route.isTunnel ? "  ⚠️ 被代理接管" : "")
        } else {
            routeSummary = "拿不到 \(config.server) 的路由"
        }
        if let chosen = interfaces.first(where: { $0.ipv4 != nil })
            ?? interfaces.first {
            routeGuarantee = RouteGuard(registeredGateway: config.currentProfile?.gateway)
                .evaluate(route: route, interface: chosen,
                          helperAuthorized: config.routeGuard.helperAuthorized == true)
        }
    }

    // MARK: 事件

    private func handle(_ event: AuthCoordinator.Event) async {
        FileLogger.shared.log("event \(event)")
        switch event {
        case .state(let next):
            state = next
            switch next {
            case .online:
                // 在线期间别被 App Nap 挂起（不然 10s 心跳会被延迟成几十秒）
                activityKeeper.begin()
                Notifier.resetDeduplication()
            case .idle, .failed:
                activityKeeper.end()
            default:
                break
            }
            if case .failed(let error) = next {
                lastError = error
                Notifier.notifyFailure(error)
            }
        case .link(let next):
            link = next
            recentLog.insert("链路：\(next.displayName)", at: 0)
        case .note(let message):
            recentLog.insert(message, at: 0)
            if recentLog.count > 50 { recentLog.removeLast() }
        case .telemetry(let telemetry):
            switch telemetry {
            case .session(let account, let clientIP, let session):
                self.clientIP = clientIP
                sessionNumber = session
                recentLog.insert("登录成功：\(account) @ \(clientIP ?? "-")", at: 0)
            case .traffic(let seconds, let stats):
                secondsOnline = seconds
                trafficStats = stats
            case .note(let message):
                recentLog.insert(message, at: 0)
            }
        }
    }

    // MARK: 网络跃迁（PLAN §6.3 / §8.6：拔插网线 ≤5s 自动恢复）

    private func observeNetworkPaths() {
        let monitor = pathMonitor
        pathTask = Task { [weak self] in
            for await event in monitor.events() {
                guard let self else { return }
                await self.handlePathEvent(event)
            }
        }
    }

    private func handlePathEvent(_ event: PathEvent) async {
        FileLogger.shared.log("path \(event)")
        switch event {
        case .becameUnsatisfied:
            // 先别急着拆：引擎会在保活/探针上很快发现；网卡回来时再统一重建
            return
        case .becameSatisfied, .interfacesChanged:
            break
        }
        guard state.isOnline || isWaitingForPath else { return }
        // 插拔 USB 网卡会连着来好几个事件，去抖一次就够
        pathDebounce?.cancel()
        pathDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !Task.isCancelled else { return }
            self.recentLog.insert("检测到网络变化，重新建立连接", at: 0)
            self.retry()
        }
    }

    /// 是否正卡在"等网络变化"的失败态（拔网线 / 网卡没地址）。
    private var isWaitingForPath: Bool {
        if case .failed(let error) = state { return error.awaitsPathChange }
        return false
    }

    // MARK: 休眠 / 唤醒（PLAN §8.3）

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recentLog.insert("系统休眠：关通道、停全部定时器（不发 Logout）", at: 0)
                self.disconnect()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recentLog.insert("系统唤醒：等 2s 后重新识别网络", at: 0)
                try? await Task.sleep(for: .seconds(2))
                self.refreshDiagnostics()
                self.connect()
            }
        }
    }
}

enum SystemHostname {
    /// 登录包 0x06E 最多 26 字节；超长必须截断（编码器不接受超长）。
    static let value: String = {
        var text = ProcessInfo.processInfo.hostName
        if !text.lowercased().hasSuffix(".local") { text += ".local" }
        while text.utf8.count > PacketLayout.Login.hostnameLength { text.removeLast() }
        return text
    }()
}
