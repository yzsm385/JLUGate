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

    @ObservationIgnored private var shouldAutoConnectOnLaunch = false
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var watchPrompted = false
    @ObservationIgnored private var lastWatchDescription: String?
    @ObservationIgnored private let connectivityProbe = ConnectivityProbe()
    /// 只观测不认证的在线状态（用户已有会话、但我们还没配账号）
    var observingExistingSession = false
    var networkSnapshot: NetworkSnapshot?
    var pingResults: [PingSummary] = []
    var speedResults: [SpeedResult] = []
    var diagnosticsBusy = false
    /// 最近一次进入在线的时间（判断"重复登录被拒"用）
    var lastOnlineAt: Date?
    var proxyAnalysis: ProxyModeAnalysis?
    var authLiveness: AuthLivenessProbe.Sample?

    /// 测认证通道：直连 vs 经默认出口（含代理/VPN）。
    func measureAuthLiveness() {
        guard !diagnosticsBusy else { return }
        diagnosticsBusy = true
        let interface = interfaces.first(where: \.isUsableForAuthentication) ?? interfaces.first
        Task { @MainActor in
            let sample = await AuthLivenessProbe().measure(interface: interface)
            authLiveness = sample
            diagnosticsBusy = false
            recentLog.insert(sample.verdict, at: 0)
            FileLogger.shared.log("认证通道：\(sample.verdict)")
        }
    }

    @ObservationIgnored private var coordinator: AuthCoordinator?
    @ObservationIgnored private var coordinatorTask: Task<Void, Never>?
    @ObservationIgnored private let portalBrowser = WKPortalBrowser()
    @ObservationIgnored private let interfacesProvider = SystemInterfaceProvider()
    @ObservationIgnored private var wizardWindow: NSWindow?
    @ObservationIgnored private var networkDetailWindow: NSWindow?
    @ObservationIgnored private var settingsWindow: NSWindow?
    @ObservationIgnored private var connectionStatusWindow: NSWindow?
    @ObservationIgnored private var portalViewerWindow: NSWindow?
    @ObservationIgnored private let activityKeeper = ActivityKeeper()
    @ObservationIgnored private let pathMonitor = PathMonitor()
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var pathDebounce: Task<Void, Never>?

    init() {
        let loaded = ConfigStore.load()
        config = loaded
        // dev 自检不碰钥匙串：ad-hoc 每次签名都不同，读旧条目会弹"允许访问钥匙串"
        password = DevOverrides.isEnabled
            ? "test-pass-2024"
            : (CredentialStore.password(for: loaded.account) ?? "")

        let profile = loaded.currentProfile
        let needsStatic = WizardPolicy.requiresStaticAddresses(link: loaded.link)
        let profileComplete = WizardPolicy.profileIsComplete(
            ip: profile?.ip, mask: profile?.mask,
            gateway: profile?.gateway, mac: profile?.registeredMAC)
        let hasAccount = !loaded.account.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPassword = !password.isEmpty

        // 记住过账号密码、并且成功连过 → 启动直接连，不打扰
        showWizard = LaunchPolicy.shouldShowWizard(
            hasAccount: hasAccount, hasPassword: hasPassword,
            linkRequiresStaticAddresses: needsStatic, profileIsComplete: profileComplete)
        // 还没配账号：先被动看一眼是不是本来就在线（浏览器里已登录的情况），
        // 不急着逼用户填密码；等真的需要认证时再请他填一次。
        if !hasAccount || !hasPassword {
            showWizard = false
            startPassiveWatch()
        }
        shouldAutoConnectOnLaunch = !DevOverrides.autostart && LaunchPolicy.shouldAutoConnect(
            hasAccount: hasAccount, hasPassword: hasPassword,
            linkRequiresStaticAddresses: needsStatic, profileIsComplete: profileComplete,
            everConnected: loaded.lastSuccessfulLogin != nil,
            autoConnectEnabled: loaded.autoConnect)
        refreshDiagnostics()
        observeSleepWake()
        observeNetworkPaths()
        if showWizard, !DevOverrides.autostart {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.presentWizard()
            }
        }
        if shouldAutoConnectOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                self.connect()
            }
        }
        if DevOverrides.openSettingsOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                self.presentSettings()
            }
        }
        if DevOverrides.openNetworkDetailOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                self.presentNetworkDetail()
            }
        }
        if DevOverrides.autostart {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.connect()
            }
        }
        Notifier.requestAuthorizationIfNeeded()

        FileLogger.shared.log("启动 JLU Gate \(BuildInfo.display)")
        FileLogger.shared.log("credential backend=\(CredentialStore.backend.rawValue)")
        if DevOverrides.isEnabled {
            let devState = "dev server=\(DevOverrides.server?.description ?? "-"):\(DevOverrides.port ?? 0)"
                + " autostart=\(DevOverrides.autostart)"
            print("JLUDev \(devState)")
            FileLogger.shared.log("start \(devState)")
        }
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
        window.setContentSize(NSSize(width: 540, height: 480))
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
        if observingExistingSession { return "当前已在线上（未配置账号）" }
        return "\(config.server):\(config.serverPort)"
    }

    var isConfigured: Bool {
        config.currentProfile?.configuredAt != nil
    }

    var canOpenPortalLogin: Bool {
        link == .jluWiFi || config.link == "jluWiFi"
    }

    // MARK: 被动观测（已有会话、未配置账号）

    /// 只做 204 探针：在线就如实显示"已连接"；需要认证时才弹一次向导。
    private func startPassiveWatch() {
        watchTask?.cancel()
        watchTask = Task { @MainActor [weak self] in
            var wasOnline = false
            while !Task.isCancelled {
                guard let self else { return }
                // 每轮都重新枚举一次网卡：启动时可能还没拿到，插拔后也会变
                self.refreshDiagnostics()
                guard let interface = self.interfaces.first(where: \.isUsableForAuthentication)
                        ?? self.interfaces.first else {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                let outcome = await self.connectivityProbe.run(interface: interface, dnsServers: [])
                if Task.isCancelled { return }
                if self.lastWatchDescription != "\(outcome)" {
                    self.lastWatchDescription = "\(outcome)"
                    FileLogger.shared.log("passive watch: \(interface.name) -> \(outcome)")
                }

                let observation: PassiveMonitor.Observation = switch outcome {
                case .healthy: .online
                case .captivePortal(let code, let location):
                    .needsAuthentication(statusCode: code, location: location)
                case .unreachable(let reason): .unreachable(reason: reason)
                }

                switch PassiveMonitor.decide(observation) {
                case .reportOnline:
                    self.observingExistingSession = true
                    if !wasOnline {
                        self.recentLog.insert("当前已在线上（无需登录），状态已更新为已连接", at: 0)
                        FileLogger.shared.log("passive watch: 已在线上，状态置为已连接")
                    }
                    wasOnline = true
                    self.state = .online
                    self.refreshDiagnostics()
                case .requestCredentials:
                    self.observingExistingSession = false
                    self.state = .idle
                    self.refreshDiagnostics()
                    if PassiveMonitor.shouldPromptOnNeedsAuth(wasOnline: wasOnline,
                                                              alreadyPrompted: self.watchPrompted) {
                        self.watchPrompted = true
                        self.recentLog.insert("检测到需要登录：请填写一次账号密码（之后会记住）", at: 0)
                        self.presentWizard()
                    }
                    wasOnline = false
                case .reportOffline(let reason):
                    self.observingExistingSession = false
                    self.state = .failed(.notCampusNetwork(detail: reason))
                    wasOnline = false
                }

                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func stopPassiveWatch() {
        watchTask?.cancel()
        watchTask = nil
        observingExistingSession = false
    }

    // MARK: 动作

    func connect() {
        stopPassiveWatch()
        watchPrompted = true
        if DevOverrides.isEnabled {
            if config.account.isEmpty { config.account = "20230001" }
            if password.isEmpty { password = "test-pass-2024" }
            if DevOverrides.portalBase != nil {
                config.link = "jluWiFi"
            } else if DevOverrides.server != nil {
                config.link = "wired"
            }
        }
        guard !config.account.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            recentLog.insert("还没有账号或密码：请先在设置里填一次（之后会自动记住）", at: 0)
            presentWizard()
            return
        }
        guard IPv4Address(config.server) != nil else {
            state = .failed(.malformed("服务器地址不合法"))
            return
        }
        // 注意：这里**不写钥匙串**。凭据只在向导/设置页保存时落盘（用户明确动作），
        // 否则每次重连都会改一次 keychain item，签名一变就会弹授权框。
        if !DevOverrides.isEnabled {
            ConfigStore.save(config)
        }

        let profile = config.currentProfile
        let devPortal = DevOverrides.portalBase
        let devServer = DevOverrides.server
        let server = devServer ?? IPv4Address(config.server)!
        let serverPort = devServer != nil ? (DevOverrides.port ?? 61441) : UInt16(config.serverPort)
        let interfaceProvider: any InterfaceProvider = devServer != nil
            ? DevLoopbackProvider()
            : interfacesProvider
        let livenessCheck: @Sendable (InterfaceSnapshot) async -> Bool = { interface in
            let outcome = await ConnectivityProbe().run(interface: interface,
                                                       dnsServers: ConnectivityProbe.fallbackDNSServers)
            if case .healthy = outcome { return true }
            return false
        }
        let engineConfiguration = EngineConfiguration(
            account: config.account,
            password: password,
            hostname: SystemHostname.value,
            registeredMAC: profile?.registeredMAC.flatMap(MACAddress.init),
            interfaceLock: devServer != nil ? "lo0" : config.interfaceLock,
            expectedIP: devServer != nil ? nil : profile?.ip.flatMap(IPv4Address.init),
            expectedMask: devServer != nil ? nil : profile?.mask,
            useRegisteredMACForAuth: config.useRegisteredMACForAuth,
            server: server,
            serverPort: serverPort,
            localPort: UInt16(config.localPort),
            keepAliveInterval: .seconds(config.keepAlive.interval),
            missTolerance: config.keepAlive.missTolerance,
            livenessCheck: livenessCheck)

        // dev 模式用 BSD：NWPath 不会把 loopback 交出来，`requiredInterface` 建不起来
        let channelFactory: any ChannelFactory = (devServer != nil || config.channel == "bsd")
            ? BSDChannelFactory()
            : NWChannelFactory()
        let backoff = Backoff(base: config.backoff.base, cap: config.backoff.cap,
                              jitter: config.backoff.jitter, maxAttempts: config.backoff.maxAttempts)
        let portalConfiguration = PortalConfiguration(
            silentRetryOnce: devPortal == nil ? config.portal.silentRetryOnce : false,
            promptCooldown: .seconds(Double(config.portal.promptCooldownSeconds)),
            probeInterval: .seconds(config.probe.interval),
            failTolerance: config.probe.failTolerance,
            dnsServers: (profile?.dns ?? []).compactMap(IPv4Address.init),
            backoff: backoff)
        let portalEntry = devPortal.map { $0.appendingPathComponent("portal?autologin=1") }
            ?? config.portal.entryURL.flatMap(URL.init(string:))
        let browser: any PortalBrowser = DevOverrides.portalUsesScriptedBrowser
            ? DevScriptedBrowser(account: config.account, password: password)
            : portalBrowser
        // 自检时把 204 探针指向本地模拟门户；生产仍用真实 ConnectivityProbe
        let portalProbe: any ConnectivityProbing = devPortal.map { DevPortalProbe(base: $0) }
            ?? ConnectivityProbe()

        let factory: @Sendable (AccessLink, InterfaceSnapshot) -> any AuthProvider = { link, _ in
            if link.usesDrcomUDP {
                let engine = DrcomEngine(configuration: engineConfiguration,
                                         codec: DrcomCodec(),
                                         channelFactory: channelFactory,
                                         interfaces: interfaceProvider,
                                         clock: SystemClock(),
                                         backoff: backoff)
                return DrcomAuthProvider(engine: engine, link: link)
            }
            return PortalEngine(probe: portalProbe,
                                browser: browser,
                                detector: PortalDetector(configuredURL: portalEntry),
                                configuration: portalConfiguration)
        }

        let devPreference: LinkPreference? = devPortal != nil ? .jluWiFi : (devServer != nil ? .wired : nil)
        let coordinatorConfiguration = AuthCoordinator.Configuration(
            preference: devPreference ?? (LinkPreference(rawValue: config.link) ?? .auto),
            autoDetect: devPreference != nil ? false : config.autoDetect,
            server: IPv4Endpoint(host: server, port: serverPort),
            localPort: UInt16(config.localPort),
            registeredMAC: profile?.registeredMAC.flatMap(MACAddress.init),
            interfaceLock: config.interfaceLock,
            dnsServers: (profile?.dns ?? []).compactMap(IPv4Address.init),
            probeTimeout: .seconds(config.probe.timeout))

        presentConnectionStatus()
        let coordinator = AuthCoordinator(configuration: coordinatorConfiguration,
                                          interfaces: interfaceProvider,
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
        stopPassiveWatch()
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

    /// JLU.WIFI 被挤下线时给用户的说明（三台上限 + 重进代价）。
    var portalLimitNotice: String? {
        guard link == .jluWiFi || (link == nil && config.link == "jluWiFi") else { return nil }
        guard !state.isOnline else { return nil }
        return JLUWiFiLimits.reclaimNotice
    }

    /// 菜单里的"重新抢回在线"（会踢掉队列第二台）。
    func reclaimPortal() {
        guard let coordinator else {
            presentWizard()
            return
        }
        Task { await coordinator.reclaimPortal() }
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

    /// 记录"这台机器上成功连过"，下次启动就静默恢复，不再让用户填账号密码。
    private func markSuccessfulLogin() {
        config.lastSuccessfulLogin = ISO8601DateFormatter().string(from: .now)
        if !DevOverrides.isEnabled {
            ConfigStore.save(config)
            // 密码可能只存在于内存（例如刚在设置里改了但没保存），顺手补存一次
            if !password.isEmpty {
                try? CredentialStore.save(password: password, account: config.account)
            }
        }
    }

    /// 只清网络参数（IP/掩码/网关/DNS/登记 MAC），账号密码保留。
    func clearNetworkParameters() {
        config.currentProfile = AppConfig.NetworkProfile(configuredAt: nil)
        persist()
        refreshDiagnostics()
        recentLog.insert("已清空本机保存的网络参数", at: 0)
        FileLogger.shared.log("清空网络参数")
    }

    /// 清掉保存的密码（连带账号名也清空？不——只清密码，账号留着方便重填）。
    func clearSavedPassword() {
        guard !config.account.isEmpty else { return }
        CredentialStore.delete(account: config.account)
        password = ""
        recentLog.insert("已删除保存的密码（本机不再记住）", at: 0)
        FileLogger.shared.log("删除已保存的密码")
    }

    /// 把本机配置恢复成出厂状态（清空 config.json、账号档案与保存的密码），然后重新走向导。
    /// 用在"配置被写坏 / 换了账号想重来"的场景。
    func resetLocalConfiguration() {
        disconnect()
        ConfigStore.delete()
        if !config.account.isEmpty { CredentialStore.delete(account: config.account) }
        config = AppConfig()
        password = ""
        showWizard = true
        routeGuarantee = nil
        recentLog.insert("已重置本机配置，请重新填写", at: 0)
        FileLogger.shared.log("配置已重置")
        presentWizard()
    }

    func finishWizard() {
        showWizard = false
        refreshDiagnostics()
        presentConnectionStatus()   // 点完成立刻有反馈
    }

    // MARK: 连接结果窗（点完成/登录后立刻给反馈）

    /// 点「完成」或「登录」之后立刻弹出来，显示进度与结果——不把错误藏在菜单栏里。
    func presentConnectionStatus() {
        if let connectionStatusWindow {
            connectionStatusWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: ConnectionStatusView().environment(self))
        let window = NSWindow(contentViewController: controller)
        window.title = "JLU Gate · 连接状态"
        window.setContentSize(NSSize(width: 440, height: 260))
        window.center()
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable]
        connectionStatusWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeConnectionStatus() {
        connectionStatusWindow?.orderOut(nil)
        connectionStatusWindow = nil
    }

    // MARK: 校园网门户（App 内查看，不自动弹）

    var portalViewerURL: URL? {
        config.portal.entryURL.flatMap(URL.init(string:))
            ?? config.portal.lastKnownURL.flatMap(URL.init(string:))
    }

    func presentPortalViewer() {
        if let portalViewerWindow {
            portalViewerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(
            rootView: PortalViewerView(url: portalViewerURL).environment(self))
        let window = NSWindow(contentViewController: controller)
        window.title = "JLU Gate · 校园网门户"
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .resizable]
        portalViewerWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 被门户拦下时记下入口地址，并把页面 HTML 缓存一份，供 App 内离线查看。
    private func rememberPortalEntry(_ url: URL) {
        config.portal.lastKnownURL = url.absoluteString
        persist()
    }

    func cachePortalPageIfPossible() async {
        guard let url = portalViewerURL else { return }
        guard let page = try? await URLSessionPortalFetcher().fetch(
            url, interface: interfaces.first ?? InterfaceSnapshot(name: "en0", index: 0, ipv4: nil,
                                                                mac: nil, isWireless: false, isUp: true))
        else { return }
        let fileURL = ConfigStore.directory.appendingPathComponent(PortalAssets.cacheFileName)
        try? FileManager.default.createDirectory(at: ConfigStore.directory,
                                                 withIntermediateDirectories: true)
        try? page.body.write(to: fileURL, atomically: true, encoding: .utf8)
        FileLogger.shared.log("已缓存门户页面：\(page.body.count) 字符")
    }

    // MARK: 设置窗口

    /// 自己开一个窗口放设置页。
    /// 不用 `SettingsLink`：LSUIElement（菜单栏常驻）的应用在部分系统版本上点了没反应，
    /// 自己建 NSWindow 更可靠，也便于把窗口置前。
    func presentSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsView().environment(self))
        let window = NSWindow(contentViewController: controller)
        window.title = "JLU Gate 设置"
        window.setContentSize(NSSize(width: 580, height: 680))
        window.center()
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable]
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        FileLogger.shared.log("打开设置窗口")
    }

    func closeSettings() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }

    // MARK: 选网卡（按 MAC 自动认，认不出就让用户选）

    /// 所有可用于认证的网卡（含出厂 MAC）。
    var interfaceCandidates: [InterfaceMACCandidate] {
        interfaces
            .filter(\.isUsableForAuthentication)
            .map { item in
                InterfaceMACCandidate(name: item.name, ipv4: item.ipv4,
                                      currentMAC: item.mac, hardwareMAC: item.hardwareMAC)
            }
    }

    var interfaceMatchingSummary: String {
        InterfaceMatching.summary(registered: config.currentProfile?.registeredMAC.flatMap(MACAddress.init),
                                  candidates: interfaceCandidates,
                                  locked: config.interfaceLock)
    }

    /// 自动认卡：命中登记 MAC 就锁定这块，避免"明明登记了还被判不匹配"。
    @discardableResult
    func autoSelectInterface() -> String? {
        let registered = config.currentProfile?.registeredMAC.flatMap(MACAddress.init)
        guard let chosen = InterfaceMatching.autoSelected(registered: registered,
                                                          candidates: interfaceCandidates) else {
            recentLog.insert(interfaceMatchingSummary, at: 0)
            return nil
        }
        config.interfaceLock = chosen
        persist()
        recentLog.insert("已按 MAC 自动选用网卡 \(chosen)", at: 0)
        FileLogger.shared.log("自动选网卡：\(chosen)")
        return chosen
    }

    /// 用"当前选中网卡的出厂 MAC"覆盖档案里的登记值（一键纠正填错的情况）。
    @discardableResult
    func adoptDetectedMAC() -> String? {
        let chosen = config.interfaceLock.flatMap { name in interfaceCandidates.first { $0.name == name } }
            ?? interfaceCandidates.first(where: { $0.ipv4 != nil })
            ?? interfaceCandidates.first
        guard let mac = chosen?.macForAuthentication else { return nil }
        var profile = config.currentProfile ?? AppConfig.NetworkProfile()
        profile.registeredMAC = mac
        config.currentProfile = profile
        if config.interfaceLock == nil { config.interfaceLock = chosen?.name }
        persist()
        recentLog.insert("已把登记 MAC 改为检测到的出厂 MAC：\(mac)", at: 0)
        FileLogger.shared.log("登记 MAC 改为 \(mac)（网卡 \(chosen?.name ?? "?")）")
        return mac
    }

    func selectInterface(_ name: String?) {
        config.interfaceLock = name
        persist()
        recentLog.insert(name.map { "已指定网卡 \($0)" } ?? "已改为自动选择网卡", at: 0)
    }

    // MARK: 自动填入静态参数（仅在系统是手动配置时可信）

    func parameterSuggestionForCurrentInterface() -> NetworkParameterSuggestion {
        let interface = interfaces.first(where: \.isUsableForAuthentication) ?? interfaces.first
        let provider = SystemInterfaceProvider()
        let method = interface.flatMap { provider.configMethod(of: $0.name) }
        let gateway = provider.defaultGateway()
        let dns = NetworkInspector.systemDNS().filter { !$0.hasPrefix("198.18.") }
        return ParameterSuggester.suggest(
            ip: interface?.ipv4,
            mask: interface?.netmask,
            mac: interface?.mac,
            configMethod: method,
            defaultGateway: gateway,
            dns: dns)
    }

    /// 一键把"系统当前（手动）配置"写进档案与向导草稿。
    @discardableResult
    func applySystemParameters() -> NetworkParameterSuggestion {
        let suggestion = parameterSuggestionForCurrentInterface()
        guard suggestion.hasUsableValues else {
            recentLog.insert(suggestion.reason, at: 0)
            return suggestion
        }
        var profile = config.currentProfile ?? AppConfig.NetworkProfile()
        profile.ip = suggestion.ip
        profile.mask = suggestion.mask
        profile.gateway = suggestion.gateway
        if !suggestion.dns.isEmpty { profile.dns = suggestion.dns }
        profile.registeredMAC = suggestion.mac
        profile.configuredAt = profile.configuredAt ?? ISO8601DateFormatter().string(from: .now)
        config.currentProfile = profile
        persist()
        refreshDiagnostics()
        recentLog.insert("已按系统手动配置填入静态参数", at: 0)
        FileLogger.shared.log("自动填入参数：\(suggestion.ip ?? "-")/\(suggestion.mask ?? "-") gw=\(suggestion.gateway ?? "-")")
        return suggestion
    }

    // MARK: 网络详情

    func presentNetworkDetail() {
        if let networkDetailWindow {
            networkDetailWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshNetworkDetail()
            return
        }
        let controller = NSHostingController(rootView: NetworkDetailView().environment(self))
        let window = NSWindow(contentViewController: controller)
        window.title = "JLU Gate · 网络详情"
        window.setContentSize(NSSize(width: 640, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable]
        networkDetailWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshNetworkDetail()
    }

    func closeNetworkDetail() {
        networkDetailWindow?.orderOut(nil)
        networkDetailWindow = nil
    }

    func refreshNetworkDetail() {
        let snapshot = NetworkInspector().snapshot()
        networkSnapshot = snapshot
        proxyAnalysis = ProxyModeAnalyzer.analyze(
            snapshot.proxyFacts(runningApps: Self.detectedProxyApps()),
            declared: DeclaredProxyMode(rawValue: config.declaredProxyMode) ?? .unknown)
        refreshDiagnostics()
    }

    /// 网络详情里解释 utun 归属时要用
    var detectedProxyAppNames: [String] { Self.detectedProxyApps() }

    /// 当前正在运行的代理 App（小火箭 / Clash / Surge …），只用于展示与归因。
    static func detectedProxyApps() -> [String] {
        let keywords = ["shadowrocket", "小火箭", "clash", "surge", "stash", "quantumult",
                        "sing-box", "v2ray", "shadowsocks", "wireguard", "tunnelblick", "openvpn"]
        // 归一化成"人看得懂的名字"：Shadowrocket Widget / Shadowrocket Helper 都算 Shadowrocket
        let canonical: [(needle: String, name: String)] = [
            ("shadowrocket", "Shadowrocket"), ("小火箭", "Shadowrocket"),
            ("clash", "Clash"), ("surge", "Surge"), ("stash", "Stash"),
            ("quantumult", "Quantumult"), ("sing-box", "sing-box"),
            ("v2ray", "V2Ray"), ("shadowsocks", "Shadowsocks"),
            ("wireguard", "WireGuard"), ("tunnelblick", "Tunnelblick"), ("openvpn", "OpenVPN"),
        ]
        var found: Set<String> = []
        for app in NSWorkspace.shared.runningApplications {
            let name = (app.localizedName ?? "") + " " + (app.bundleIdentifier ?? "")
            let lowered = name.lowercased()
            guard keywords.contains(where: { lowered.contains($0) }) else { continue }
            if let match = canonical.first(where: { lowered.contains($0.needle) }) {
                found.insert(match.name)
            }
        }
        return found.sorted()
    }

    func setDeclaredProxyMode(_ raw: String) {
        config.declaredProxyMode = raw
        persist()
        refreshNetworkDetail()
    }

    func runPing() {
        guard !diagnosticsBusy else { return }
        diagnosticsBusy = true
        let snapshot = networkSnapshot ?? NetworkInspector().snapshot()
        let interface = interfaces.first(where: \.isUsableForAuthentication) ?? interfaces.first
        Task { @MainActor in
            let service = PingService()
            var results: [PingSummary] = []
            for target in PingTarget.defaults(snapshot: snapshot) {
                let pair = await service.compare(target, interface: interface)
                results.append(pair.direct)
                results.append(PingSummary(host: "经默认出口 " + pair.viaDefault.host,
                                           latencies: pair.viaDefault.latencies,
                                           attempted: pair.viaDefault.attempted))
            }
            pingResults = results
            diagnosticsBusy = false
            FileLogger.shared.log("网络详情：Ping 完成 \(results.count) 项")
        }
    }

    func runSpeedTest() {
        guard !diagnosticsBusy else { return }
        diagnosticsBusy = true
        let interface = interfaces.first(where: \.isUsableForAuthentication) ?? interfaces.first
        Task { @MainActor in
            let results = await SpeedTestService().compare(interface: interface)
            speedResults = results
            diagnosticsBusy = false
            FileLogger.shared.log("网络详情：测速完成 \(results.count) 项")
        }
    }

    func copyNetworkDetail() {
        guard let snapshot = networkSnapshot else { return }
        var lines: [String] = ["JLU Gate 网络详情", ""]
        for row in snapshot.interfaces {
            lines.append("\(row.name) ifindex=\(row.index) ipv4=\(row.ipv4 ?? "-")/\(row.mask ?? "-") mac=\(row.mac ?? "-") 无线=\(row.isWireless) USB=\(row.isUSB)")
        }
        for tunnel in snapshot.tunnels {
            lines.append("隧道 \(tunnel.name) ipv4=\(tunnel.ipv4 ?? "-") up=\(tunnel.isUp)")
        }
        lines.append("默认出口：\(snapshot.defaultRoute?.interface ?? "-")")
        lines.append("认证出口：\(snapshot.campusRoute?.interface ?? "-")")
        lines.append("系统 DNS：\(snapshot.dnsServers.joined(separator: ", "))")
        for summary in pingResults { lines.append(summary.description) }
        for result in speedResults { lines.append(result.description) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        recentLog.insert("已复制网络详情", at: 0)
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
                lastOnlineAt = Date()
                // 在线期间别被 App Nap 挂起（不然 10s 心跳会被延迟成几十秒）
                activityKeeper.begin()
                Notifier.resetDeduplication()
                markSuccessfulLogin()
            case .idle, .failed:
                activityKeeper.end()
            default:
                break
            }
            if case .failed(let error) = next {
                lastError = error
                Notifier.notifyFailure(error)
                // "账号已在别处登录"这类失败，如果本机网络其实通着（会话还在），
                // 不要把徽标打回"未连接"——服务器常常只是重复登录时报这个。
                let isAccountConflict: Bool = {
                    if case .accountInUse = error { return true }
                    if case .macInUse = error { return true }
                    return false
                }()
                // 认证被拒 ≠ 网络不可用：只要真实探测通过，就按"已连接"处理，
                // 否则用户会看到"能上网却显示未连接"，而且下次启动也不会自动连。
                let offlineReason: Bool = {
                    if case .notCampusNetwork = error { return true }
                    if case .adapterUnplugged = error { return true }
                    if case .interfaceHasNoIPv4 = error { return true }
                    return false
                }()
                if !offlineReason, await probeReachable() {
                    state = .online
                    markSuccessfulLogin()
                    recentLog.insert("认证没有明确成功，但网络实际可用：按已连接处理（服务器原话：\(error.userMessage)）", at: 0)
                    FileLogger.shared.log("probe healthy after failure -> online; server said: \(error.userMessage)")
                }
            }
        case .link(let next):
            link = next
            recentLog.insert("链路：\(next.displayName)", at: 0)
            if next == .jluWiFi, let coordinator {
                if let entry = await coordinator.currentPortalEntry() {
                    rememberPortalEntry(entry)
                }
            }
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
                if portalViewerURL != nil, seconds <= 2 {
                    Task { await self.cachePortalPageIfPossible() }
                }
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
        pathDebounce?.cancel()
        pathDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2000))
            guard let self, !Task.isCancelled else { return }
            // 已经在线：网卡集合抖一下不代表会话失效，先探测再决定
            if self.state.isOnline {
                if await self.probeReachable() {
                    self.recentLog.insert("网络有变化，但探测仍正常：保持在线", at: 0)
                    FileLogger.shared.log("path changed but probe healthy: keep online")
                    return
                }
                self.recentLog.insert("网络变化且探测失败：重新建立连接", at: 0)
            }
            self.retry()
        }
    }

    /// 最近 10 分钟内成功在线过（用于判断"重复登录被拒"是不是误报）
    private var wasEverOnlineRecently: Bool {
        guard let at = lastOnlineAt else { return false }
        return Date().timeIntervalSince(at) < 600
    }

    /// 用真实探测判断"现在到底通不通"（不依赖引擎内部状态）。
    func probeReachable() async -> Bool {
        let interface = interfaces.first { $0.name == config.interfaceLock }
            ?? interfaces.first(where: \.isUsableForAuthentication)
            ?? interfaces.first
        guard let interface else { return false }
        let outcome = await ConnectivityProbe().run(interface: interface,
                                                    dnsServers: ConnectivityProbe.fallbackDNSServers)
        if case .healthy = outcome { return true }
        return false
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
