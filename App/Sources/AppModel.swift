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
    var routeSummary: String = Copy.t("B501")
    var routeGuarantee: RouteGuarantee?
    var showWizard = false
    /// 菜单栏面板当前是否展开（关闭时不跑每秒刷新）
    var isPanelVisible = false

    /// 面板内容：**所有界面都放在菜单栏面板里**，不再自建 NSWindow。
    /// 真机崩溃栈（AppKit display cycle + objc_exception_rethrow）指向自建窗口的布局，
    /// 面板路径是被长期验证可用的，所以统一改成"面板内切换"。
    enum Panel: Equatable {
        case main
        case wizard
        case settings
        case detail
        case status
        case inspect
        case sites
        case developer
        case portal
        case portalLogin
    }

    private(set) var panel: Panel = .main

    // MARK: 检查更新

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(tag: String, name: String, page: URL?, asset: URL?)
        case failed(String)
    }
    var updateStatus: UpdateStatus = .idle
    private var updateChecker = UpdateChecker(wantsCompatAsset: BuildInfo.isCompatBuild)

    /// 一键更新状态文案
    var updateInstallMessage: String?
    /// 正在下载/解压/准备替换（这时别再点「更新」）
    var updateInstalling = false

    func installAvailableUpdate(page: URL?, asset: URL?) {
        guard let asset else {
            if let page { NSWorkspace.shared.open(page) }
            updateInstallMessage = "这个版本没有可用的安装包，已打开下载页"
            return
        }
        updateInstalling = true
        updateInstallMessage = "开始下载…"
        UpdateInstaller.install(from: asset) { message in
            Task { @MainActor in self.updateInstallMessage = message }
        } onFailure: { message in
            Task { @MainActor in
                self.updateInstalling = false
                self.updateInstallMessage = message
            }
        } onReadyToQuit: {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    /// 面板上那个「更新」：一步到位——查最新 → 有新版就下载替换，没新版就直说。
    func updateNow() {
        if case .available(_, _, let page, let asset) = updateStatus {
            installAvailableUpdate(page: page, asset: asset)
            return
        }
        guard updateStatus != .checking else { return }
        updateStatus = .checking
        updateInstallMessage = nil
        Task { @MainActor in
            let release = await updateChecker.latest(forceRefresh: true)
            guard let release else {
                updateStatus = .failed("查不到更新（网络或 GitHub 限流），稍后再试")
                return
            }
            if UpdateVersion.isNewer(release.tag, than: BuildInfo.version) {
                updateStatus = .available(tag: release.tag, name: release.name,
                                          page: release.pageURL, asset: release.assetURL)
                installAvailableUpdate(page: release.pageURL, asset: release.assetURL)
            } else {
                updateStatus = .upToDate
                updateInstallMessage = "已经是最新版本（v\(BuildInfo.version)）"
            }
        }
    }

    func checkForUpdates(force: Bool = false) {
        guard updateStatus != .checking else { return }
        updateStatus = .checking
        Task { @MainActor in
            let release = await updateChecker.latest(forceRefresh: force)
            guard let release else {
                updateStatus = .failed("查不到更新（网络或 GitHub 限流），稍后再试")
                return
            }
            if UpdateVersion.isNewer(release.tag, than: BuildInfo.version) {
                updateStatus = .available(tag: release.tag, name: release.name,
                                          page: release.pageURL, asset: release.assetURL)
            } else {
                updateStatus = .upToDate
            }
        }
    }

    /// 是否处在"非校园网"：**只认引擎的判定**。
    /// 不能用体检结果推断——体检里校内网站打不开可能只是代理/DNS 问题，
    /// 明明插着网线在校园网里，却被提示"你现在不在校园网"是错的。
    var isOffCampus: Bool {
        if case .failed(let error) = state, case .notCampusNetwork = error { return true }
        // 有线网卡有地址且到认证服务器走物理口 → 就在校园网
        if let routeInterfaceName,
           let wired = interfaces.first(where: { $0.name == routeInterfaceName }),
           wired.ipv4 != nil, !wired.isWireless {
            return false
        }
        return false
    }

    /// 账号 + 本机密码（曾成功登录过）都在：不需要再提示"填写账号密码"
    var hasStoredCredentials: Bool {
        guard !config.account.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let stored = CredentialStore.password(for: config.account), !stored.isEmpty else { return false }
        return CredentialStore.verifiedAt(account: config.account) != nil
    }

    // MARK: 界面语言

    /// "system" 表示跟随系统
    var languageCode: String { Copy.storedOverride?.rawValue ?? "system" }

    /// 切换界面语言（存进偏好，App 重建面板后立即生效）
    func setLanguage(_ code: String) {
        Copy.storedOverride = (code == "system") ? nil : CopyLanguage(rawValue: code)
        FileLogger.shared.log("界面语言切换为 \(languageCode)")
    }

    /// 站点合集里"复制账号"用
    var account: String { config.account }

    /// GPA / 保研测算网页。账号只放在 fragment，避免出现在服务器日志里。
    var gpaURL: URL {
        var c = URLComponents(string: "https://yzsm385.github.io/JLUGate/")!
        let a = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { c.fragment = "account=" + a }
        return c.url!
    }

    // MARK: 我的学院（学号识别）

    var studentID: String { config.studentID }

    /// 当前认出来的学院：手动选的优先，其次按学号前缀学习结果
    var myCollege: College? {
        if !config.myCollegeHost.isEmpty,
           let manual = CollegeDirectory.college(forHost: config.myCollegeHost) {
            return manual
        }
        return CollegeResolver.resolve(studentID: config.studentID,
                                       learned: config.collegePrefixMap)
    }

    func updateStudentID(_ text: String) {
        config.studentID = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ConfigStore.save(config)
    }

    /// 选定学院：写入手动值，同时把学号前缀学下来
    func setMyCollege(_ college: College) {
        config.myCollegeHost = college.host
        if !config.studentID.isEmpty {
            CollegeResolver.learn(studentID: config.studentID, college: college,
                                  into: &config.collegePrefixMap)
        }
        ConfigStore.save(config)
        FileLogger.shared.log("我的学院：设为 \(college.name)（\(college.host)）")
    }

    func clearMyCollege() {
        config.myCollegeHost = ""
        ConfigStore.save(config)
    }

    /// 上一次连接因"凭据被拒"失败：向导只允许重新输入，不再提供"使用已保存的密码"
    var requirePasswordReentry = false

    /// 设置页显示用：已保存密码的"长度 + 指纹"（不显示密码本身）
    var storedPasswordSummary: String? {
        guard !config.account.isEmpty,
              let stored = CredentialStore.password(for: config.account), !stored.isEmpty else {
            return nil
        }
        return PasswordFingerprint.describe(stored)
    }

    /// 站点合集里"复制密码"用：只读本机保存的那份，绝不落日志。
    func storedPasswordForPrefill() -> String? {
        CredentialStore.password(for: config.account)
    }

    /// 切面板统一延后一跳：按钮动作里立即改布局尺寸会落在 AppKit 的 display cycle 内。
    func show(_ next: Panel) {
        Task { @MainActor in
            self.panel = next
            FileLogger.shared.log("面板 -> \(next)")
        }
    }
    /// 正在等待用户完成的网页认证（面板内渲染）
    private(set) var pendingPortalLoginURL: URL?
    @ObservationIgnored private var portalLoginContinuation:
        CheckedContinuation<PortalLoginResult, Never>?

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
    /// 上次启动闪退后进入的安全模式（不自动连、不读密码）
    var isSafeMode = false
    struct Inspection: Equatable {
        var publicIPs: [PublicIPSample] = []
        var cloudflare: CloudflareTrace?
        var webRTC: WebRTCSample?
        var dns: DNSLeakSample?
        var captcha: [EndpointCheck] = []
    }

    var inspection = Inspection()
    var inspectionRunning = false
    /// 每个体检模块的耗时（毫秒）
    var inspectionTimings: [String: Int] = [:]

    /// 「能不能上网」的分层排查结果
    var reachability: [SiteResult] = []
    var reachabilityDiagnosis: ReachabilityDiagnosis?
    var reachabilityRunning = false

    /// 出口 IP 纯净度（住宅 / 机房）
    var ipReputation: IPReputation?
    /// 多源归属交叉
    var geoConsensus: GeoConsensus?
    /// DNS 出口与 IP 出口是否吻合
    var dnsAlignment: DNSIPAlignment?
    /// BiliBili 看到的出口（可能与代理出口不同，说明分流）
    var bilibiliObservation: GeoSourceSample?
    var bilibiliAddr: String?
    /// 带宽三档：直连、默认出口、本地代理（可选）
    var speedDirect: SpeedResult?
    var speedViaDefault: SpeedResult?
    var speedViaProxy: SpeedResult?
    var speedRunning = false
    var speedProxy = ""          // 形如 127.0.0.1:7890（留空则自动检测）
    /// 自动检测到的本地代理（供测速第三档使用）
    var detectedProxy: LocalProxyCandidate?

    func runSpeedAll() {
        guard !speedRunning else { return }
        speedRunning = true
        FileLogger.shared.log("带宽：开始，proxy=\(speedProxy.isEmpty ? "无" : speedProxy)")
        Task { @MainActor in
            let service = SpeedTestService()
            let endpoint = SpeedEndpoint.defaults[0]
            let interface = self.interfaces.first(where: \.isUsableForAuthentication)
            if self.speedProxy.isEmpty {
                self.detectedProxy = LocalProxyDetector.detect()
                if let detected = self.detectedProxy { self.speedProxy = detected.hostPort }
            }
            self.speedDirect = await service.download(endpoint: endpoint, interface: interface)
            self.speedViaDefault = await service.download(endpoint: endpoint, interface: nil)
            if !self.speedProxy.isEmpty {
                self.speedViaProxy = await service.download(endpoint: endpoint, interface: nil,
                                                            proxy: self.speedProxy)
            } else {
                self.speedViaProxy = nil
            }
            self.speedRunning = false
            FileLogger.shared.log("带宽：完成")
        }
    }

    func lookupReputation() {
        Task { @MainActor in
            await self.refreshReputation()
        }
    }

    /// 多源归属 + 纯净度 + DNS/IP 吻合度，一次算完。
    func refreshReputation() async {
        guard let ip = inspection.cloudflare?.ip else { return }
        let options = IPReputationService.Options(ip2locationKey: config.ip2locationKey,
                                                  maxmindAccount: config.maxmindAccount,
                                                  maxmindLicense: config.maxmindLicense)
        let service = IPReputationService()
        geoConsensus = await service.geoConsensus(ip: ip, options: options)
        if let zone = await service.bilibiliZone() {
            bilibiliObservation = zone.sample
            bilibiliAddr = zone.addr
        }
        ipReputation = await service.lookup(ip: ip,
                                            cloudflareCountry: inspection.cloudflare?.location)
        // DNS 出口的地理位置（用于比对）
        var dnsCountry: String?
        if let dnsEgress = inspection.dns?.systemEgress {
            let consensus = await service.geoConsensus(ip: dnsEgress, options: options)
            dnsCountry = consensus.country
        }
        dnsAlignment = DNSIPAlignmentEngine.align(ip: ip,
                                                  ipCountry: geoConsensus?.country ?? ipReputation?.country,
                                                  dnsEgress: inspection.dns?.systemEgress,
                                                  dnsCountry: dnsCountry)
    }

    func runReachability() {
        Task { @MainActor in await self.runReachabilityInline() }
    }

    /// 内部实现：体检流程也会直接调用它
    func runReachabilityInline() async {
        guard !reachabilityRunning else { return }
        reachabilityRunning = true
        FileLogger.shared.log("排查：开始")
        do {
            let results = await ReachabilityService().checkAll()
            self.reachability = results
            let interface = self.interfaces.first(where: \.isUsableForAuthentication)
            let route = interface.flatMap { _ in
                self.interfacesProvider.route(to: PacketLayout.defaultServer)
            }
            let needsCampus = self.config.link == "wired" || self.config.link == "jluPC"
            let campusReachable: Bool? = needsCampus ? await self.campusServerReachable() : nil
            self.reachabilityDiagnosis = ReachabilityDiagnosisEngine.diagnose(
                sites: results,
                campusAuthReachable: campusReachable,
                hasUsableInterface: interface != nil,
                proxyInUse: route?.isTunnel ?? false)
            self.reachabilityRunning = false
            FileLogger.shared.log("排查：\(self.reachabilityDiagnosis?.summary ?? "-")")
        }
    }

    static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private func campusServerReachable() async -> Bool {
        let interface = interfaces.first(where: \.isUsableForAuthentication)
        let sample = await AuthLivenessProbe().measure(interface: interface, attempts: 1,
                                                        timeout: .seconds(2))
        return sample.direct.average != nil
    }

    /// 官方 Dr.Com 客户端占着 61440（说明它可能在替你上网）
    var portHeldByOfficialClient = false
    /// 在线是由官方客户端维持的（端口在它手里）
    var onlineViaOfficialClient = false
    /// 最近一次服务器拒绝凭据的时间（用于界面提示）
    var credentialRejectedAt: Date?

    /// 本次登录用的是哪份密码（绝不记录密码本身）
    enum PasswordSource: String, Sendable {
        case typed = "本次输入"
        case savedVerified = "已保存（曾成功登录）"
        case savedUnverified = "已保存（未验证）"
        case savedStale = "已保存（上次被服务器拒绝）"
    }
    var passwordSource: PasswordSource = .typed
    /// 最近一次真实探测成功 / 失败的时间（用于状态粘性）
    var lastHealthyProbeAt: Date?
    var lastFailedProbeAt: Date?
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
    /// 掉线自动重连：连续第几次、以及等待中的任务
    @ObservationIgnored private var autoReconnectAttempt = 0
    @ObservationIgnored private var autoReconnectTask: Task<Void, Never>?
    /// 在线巡检：每 25 秒确认一次"外网真的还在"，连续两次被门户拦下就重新认证
    @ObservationIgnored private var onlineWatchTask: Task<Void, Never>?
    /// 最近一次"静默断网"强制重连的时间（防止探测目标被拦时反复重登）
    @ObservationIgnored private var lastForcedReauthAt: Date?
    /// 最近一次收到网关保活应答的时间（用来发现"包停了"）
    @ObservationIgnored private var lastTrafficAt: Date?
    @ObservationIgnored private lazy var portalBrowser = WKPortalBrowser(model: self)
    @ObservationIgnored private let interfacesProvider = SystemInterfaceProvider()
    @ObservationIgnored private let activityKeeper = ActivityKeeper()
    @ObservationIgnored private let pathMonitor = PathMonitor()
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var pathDebounce: Task<Void, Never>?

    init() {
        let loaded = ConfigStore.load()
        config = loaded
        // 上一次启动闪退过：进安全模式，不自动连、不读密码，先让用户能把配置改回来
        let safeMode = LaunchGuard.beginLaunch()
        // 闪退后自动关掉液态玻璃（最可能的渲染诱因），保证下次一定能进来改配置
        AppearanceCompat.apply(configFlag: loaded.compatibilityMode || safeMode)
        isSafeMode = safeMode
        if safeMode {
            FileLogger.shared.log("安全模式：跳过自动连接与密码恢复")
        } else {
            // 每次启动都对一遍登录项：配置里开着就确保系统里真的登记了。
            // 以前只有点「保存」才会注册，于是"设置里明明是开的、重启就是不启动"。
            LoginItem.apply(enabled: loaded.launchAtLogin)
        }
        // **不在启动时把保存的密码读进内存。**
        // 之前这里预加载，connect() 看到 password 非空就当成"本次输入"，
        // 于是服务器每次收到的都是那份旧密码——界面显示成点号，用户以为是自己刚输的。
        // 现在内存里只有"这次真的输入过"的密码；保存的那份只在连接时按需取，并标好来源。
        password = (DevOverrides.isEnabled && !safeMode) ? "test-pass-2024" : ""

        // 配置里的账号为空、但本机还存过密码 → 把账号找回来（换机/重置不至于让用户重填）
        if loaded.account.trimmingCharacters(in: .whitespaces).isEmpty {
            let known = CredentialStore.knownAccounts()
            if known.count == 1, let only = known.first {
                config.account = only
                ConfigStore.save(config)
                FileLogger.shared.log("配置里的账号为空：已从凭据库恢复账号 \(Redact.account(only))")
            }
        }

        let profile = loaded.currentProfile
        let needsStatic = WizardPolicy.requiresStaticAddresses(link: loaded.link)
        let profileComplete = WizardPolicy.profileIsComplete(
            ip: profile?.ip, mask: profile?.mask,
            gateway: profile?.gateway, mac: profile?.registeredMAC)
        let hasAccount = !loaded.account.trimmingCharacters(in: .whitespaces).isEmpty
        // 启动时内存里不再预加载密码，但"已验证的保存密码"仍然算有凭据，
        // 否则双击打开 App 也不会自动连（这才是"每次都要手动点"的原因之一）。
        let savedVerifiedPassword = hasAccount
            && CredentialStore.verifiedAt(account: loaded.account) != nil
            && !(CredentialStore.password(for: loaded.account) ?? "").isEmpty
        let hasPassword = !password.isEmpty || savedVerifiedPassword

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
        shouldAutoConnectOnLaunch = !safeMode && !DevOverrides.autostart && LaunchPolicy.shouldAutoConnect(
            hasAccount: hasAccount, hasPassword: hasPassword,
            linkRequiresStaticAddresses: needsStatic, profileIsComplete: profileComplete,
            everConnected: loaded.lastSuccessfulLogin != nil,
            autoConnectEnabled: loaded.autoConnect)
        scheduleInitialDiagnostics()
        observeSleepWake()
        observeNetworkPaths()
        FileLogger.shared.log("启动决策：账号=\(hasAccount) 密码=\(hasPassword)"
                              + "（已验证保存=\(savedVerifiedPassword)） 静态参数完整=\(profileComplete)"
                              + " 需要向导=\(showWizard) 自动连接=\(shouldAutoConnectOnLaunch)")
        if showWizard, !DevOverrides.autostart {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.presentWizard()
            }
        }
        if shouldAutoConnectOnLaunch {
            scheduleLaunchAutoConnect()
        }
        if DevOverrides.uiProbeOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                self.runUIProbe()
            }
        }
        if DevOverrides.saveWiredOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                self.devSimulateWiredSave()
            }
        }
        if DevOverrides.runInspectOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                self.runInspection()
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
        if safeMode {
            recentLog.insert("上次启动异常退出，已进入安全模式：不自动连接、不读取已保存的密码。请检查设置或重置本机配置。", at: 0)
        }
        Notifier.requestAuthorizationIfNeeded()
        // 初始化走完 3 秒还没崩，说明这一版能正常启动
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            LaunchGuard.markLaunchSucceeded()
        }

        FileLogger.shared.log("启动 JLU Gate \(BuildInfo.display)")
        FileLogger.shared.log("credential backend=\(CredentialStore.backend.rawValue)")
        FileLogger.shared.log("配置载入：账号=\(Redact.account(config.account)) 链路=\(config.link) "
                              + "服务器=\(config.server):\(config.serverPort) "
                              + "档案=\(config.accounts.count) 份")
        if DevOverrides.isEnabled {
            let devState = "dev server=\(DevOverrides.server?.description ?? "-"):\(DevOverrides.port ?? 0)"
                + " autostart=\(DevOverrides.autostart)"
            print("JLUDev \(devState)")
            FileLogger.shared.log("start \(devState)")
        }
    }

    /// 向导要直接停在"网络参数"这一步（有线没地址时）
    var wizardStartsAtNetwork = false
    /// 向导顶部提示（说明为什么要用户填参数）
    var wizardNotice: String?

    /// 首次启动 / 换账号时的向导窗口（PLAN §9.1）。
    /// 开机/启动后的自动连接：几秒后开始，失败就隔几秒重试，最多 5 次。
    /// 只在"还没在线、没有手动在连"时动作，避免打架。
    private var launchConnectTask: Task<Void, Never>?

    private func scheduleLaunchAutoConnect() {
        launchConnectTask?.cancel()
        launchConnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 等网卡枚举完再连：启动时诊断在后台跑，太早 connect 会拿到空列表
            await self.refreshDiagnosticsAsync()
            for attempt in 1...5 {
                let delay: Duration = attempt == 1 ? .seconds(1) : .seconds(2)
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
                if self.state.isOnline || self.state.isBusy { return }
                FileLogger.shared.log("开机自动连接：第 \(attempt)/5 次尝试")
                self.connect()
                try? await Task.sleep(for: .seconds(2))
                if self.state.isOnline { return }
            }
            FileLogger.shared.log("开机自动连接：5 次都没成功，等用户手动重试")
        }
    }

    func presentWizard() {
        showWizard = true
        show(.wizard)
        FileLogger.shared.log("面板：向导")
        // 面板可能在用户点开时才出现，这里不主动激活窗口
    }

    // MARK: 派生显示

    /// 当前状态的人话叙述（标题 + 一句比喻 + 该做什么）
    var statusPhase: StatusPhase {
        switch state {
        case .idle:
            return .idle
        case .discovering, .challenging, .authenticating, .reconnecting:
            return .working
        case .online:
            return onlineViaOfficialClient ? .onlineViaOfficialClient : .online
        case .failed(let error):
            // 刚探测通过/刚在线过 → 不把图标打回红色（真机上出现过 灰→绿→红 乱跳）
            if StatusStickiness(lastHealthyProbeAt: lastHealthyProbeAt,
                                lastFailedProbeAt: lastFailedProbeAt).shouldStayOnline() {
                return onlineViaOfficialClient ? .onlineViaOfficialClient : .online
            }
            switch error {
            case .adapterUnplugged, .interfaceHasNoIPv4:
                return .waitingForNetwork
            case .officialClientRunning, .localPortInUse:
                return onlineViaOfficialClient ? .onlineViaOfficialClient : .officialClientHoldingPort
            default:
                return .failed
            }
        }
    }

    var statusStory: StatusStory { StatusNarrator.story(statusPhase) }

    var statusTitle: String { statusStory.title }

    /// 图标与颜色也按 statusPhase 走，避免出现"文字说已连接、图标却是红色"
    var statusColor: Color {
        switch statusPhase {
        case .online, .onlineViaOfficialClient: .green
        case .working: .orange
        case .waitingForNetwork, .failed: .red
        case .officialClientHoldingPort: .orange
        case .idle: .secondary
        }
    }

    var statusSymbol: String {
        switch statusPhase {
        case .online, .onlineViaOfficialClient: "checkmark.circle.fill"
        case .working: "arrow.triangle.2.circlepath"
        case .waitingForNetwork: "cable.connector.slash"
        case .officialClientHoldingPort: "exclamationmark.circle"
        case .failed: "xmark.circle.fill"
        case .idle: "circle.dashed"
        }
    }

    var linkTitle: String {
        link?.displayName ?? (config.link == "auto" ? Copy.t("B506") : config.link)
    }

    var detailLine: String {
        if case .failed(let error) = state { return error.userMessage }
        if let clientIP { return Copy.f("B507", clientIP) }
        if observingExistingSession { return Copy.t("B508") }
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
            var unreachableStreak = 0
            while !Task.isCancelled {
                guard let self else { return }
                // 每轮都重新枚举一次网卡：启动时可能还没拿到，插拔后也会变。
                // 走后台版：子进程卡住也不能卡 main（否则图标/面板全出不来）。
                await self.refreshDiagnosticsAsync()
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

                // 连续 2 次不可达才判离线：单次探测抖动不该让界面变红
                if case .unreachable = observation {
                    unreachableStreak += 1
                    if unreachableStreak < 2 {
                        try? await Task.sleep(for: .seconds(5))
                        continue
                    }
                } else {
                    unreachableStreak = 0
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

    /// 自检：把每个面板视图都建一次并强制布局，验证视图本身不会崩。
    func runUIProbe() {
        FileLogger.shared.log("ui-probe: 开始")
        let probes: [(String, AnyView)] = [
            ("wizard", AnyView(WizardView().environment(self))),
            ("settings", AnyView(SettingsView().environment(self))),
            ("detail", AnyView(NetworkDetailView().environment(self))),
            ("status", AnyView(ConnectionStatusView().environment(self))),
            ("sites", AnyView(SitesPanel().environment(self))),
            ("portal", AnyView(PortalViewerView(url: portalViewerURL).environment(self))),
            ("portalLogin", AnyView(PortalLoginPanel(url: URL(string: "https://login.jlu.edu.cn")!)
                .environment(self))),
        ]
        for (name, view) in probes {
            let host = NSHostingView(rootView: view)
            // 按"面板内"的真实宽度布局（380 宽），验证不会撑爆
            host.frame = NSRect(x: 0, y: 0, width: 380, height: 560)
            host.layoutSubtreeIfNeeded()
            FileLogger.shared.log("ui-probe: \(name) 布局完成")
        }
        FileLogger.shared.log("ui-probe: 全部通过")
    }

    /// 自检用：完全走一遍"设置页保存"的写入路径（含落盘、凭据、登录项、刷新诊断）。
    func devSimulateWiredSave() {
        FileLogger.shared.log("dev: 模拟有线保存开始")
        var draft = config
        draft.link = "wired"
        draft.account = config.account.isEmpty ? "20230001" : config.account
        draft.currentProfile = AppConfig.NetworkProfile(
            ip: "192.0.2.10", mask: "255.255.255.0", gateway: "192.0.2.1",
            dns: ["10.10.10.10"], registeredMAC: "02:00:00:00:00:01",
            interfaceHint: "en0", configuredAt: ISO8601DateFormatter().string(from: .now))
        draft.accounts[draft.account] = draft.currentProfile
        config = draft
        persist()
        FileLogger.shared.log("dev: 配置已落盘")
        LoginItem.apply(enabled: config.launchAtLogin)
        FileLogger.shared.log("dev: 登录项已应用")
        refreshDiagnostics()
        FileLogger.shared.log("dev: 诊断已刷新")
        autoSelectInterface()
        FileLogger.shared.log("dev: 网卡自动选择完成 -> \(config.interfaceLock ?? "nil")")
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
        // 密码框为空但本机存过 → 只有"曾经成功登录过"的那份才允许自动复用。
        // 未验证的（从没成功过、或上次被拒）一律不静默使用：否则会拿着同一串错密码
        // 反复撞服务器，用户看到的就是"怎么点都失败"。
        if password.isEmpty, let stored = CredentialStore.password(for: config.account),
           !stored.isEmpty {
            if CredentialStore.verifiedAt(account: config.account) != nil {
                password = stored
                passwordSource = .savedVerified
                FileLogger.shared.log("使用已验证的保存密码（\(PasswordFingerprint.describe(stored))）")
            } else {
                requirePasswordReentry = true
                passwordSource = .savedUnverified
                FileLogger.shared.log("保存的密码未验证过（\(PasswordFingerprint.describe(stored))）："
                                      + Copy.t("B509"))
                recentLog.insert("本机保存的密码从未成功登录过（指纹 \(PasswordFingerprint.of(stored))）。"
                                 + Copy.t("B510"), at: 0)
                presentWizard()
                return
            }
        } else if !password.isEmpty {
            passwordSource = .typed
            FileLogger.shared.log("使用本次输入的密码（\(PasswordFingerprint.describe(password))）")
        }
        guard !config.account.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            recentLog.insert("还没有账号或密码：请先在设置里填一次（之后会自动记住）", at: 0)
            presentWizard()
            return
        }
        guard IPv4Address(config.server) != nil else {
            state = .failed(.malformed(Copy.t("B511")))
            return
        }
        // 网线被拔掉时 interfaces 会变空：此时启动引擎只会立刻报错，
        // 而且在没有物理口的瞬间做通道/探针操作容易触发底层异常——先挡在这里。
        if DevOverrides.server == nil, interfaces.isEmpty {
            state = .failed(.adapterUnplugged(interface: config.interfaceLock ?? "en*"))
            recentLog.insert("没有检测到可用的物理网口（网线可能被拔掉）。插回网线后点「重试」。", at: 0)
            FileLogger.shared.log("connect：没有物理网口，跳过本次认证")
            return
        }

        // 注意：这里**不写钥匙串**。凭据只在向导/设置页保存时落盘（用户明确动作），
        // 否则每次重连都会改一次 keychain item，签名一变就会弹授权框。
        if !DevOverrides.isEnabled {
            ConfigStore.save(config)
        }

        // 官方 Dr.Com 客户端占着 61440 且网络是通的 → 直接用"已连接（官方客户端在管）"，
        // 不再发认证包（否则会失败一次，界面就跳红一次）。
        if config.link == "wired" || config.link == "jluPC" || config.link == "auto" {
            if case .officialClient(let process, let pid) = BSDChannel.diagnosePort(PacketLayout.localPort) {
                let detail = pid.map { "\(process)(\($0))" } ?? process
                portHeldByOfficialClient = true
                onlineViaOfficialClient = true
                state = .online
                recentLog.insert("官方客户端 \(detail) 正在维持连接：已按「已连接」显示，未重复认证", at: 0)
                FileLogger.shared.log("connect：端口被官方客户端占用（\(detail)），跳过本次认证")
                // 顺手确认网络确实可达（失败也不推翻结论，官方客户端通常就是在保住它）
                Task { @MainActor in _ = await self.probeReachable() }
                return
            }
        }

        let profile = config.currentProfile
        let devPortal = DevOverrides.portalBase
        let devServer = DevOverrides.server
        let server = devServer ?? IPv4Address(config.server)!
        let serverPort = devServer != nil ? (DevOverrides.port ?? 61441) : UInt16(config.serverPort)
        let interfaceProvider: any InterfaceProvider = devServer != nil
            ? DevLoopbackProvider()
            : interfacesProvider
        let campusDNS = (profile?.dns ?? []).compactMap(IPv4Address.init).first
        let livenessCheck: @Sendable (InterfaceSnapshot) async -> Bool = { interface in
            // 只认 204：拿到 204 才算"已认证、真能上网"。
            // 被门户拦下（302/200）= 会话没了——这时校内 DNS / 网关仍然应达，
            // 以前拿它们当证据，就会把"断网"判成"在线"，然后永远不重登。
            let probe = ConnectivityProbe(targets: [.cn204, .cloudflare, .gstatic],
                                          timeout: .seconds(2))
            var servers: [IPv4Address] = []
            if let campusDNS { servers.append(campusDNS) }
            servers.append(contentsOf: ConnectivityProbe.fallbackDNSServers)
            let outcome = await probe.run(interface: interface, dnsServers: servers)
            switch SessionLiveness.verdict(outcome) {
            case .online:
                return true
            case .offline:
                return false
            case .inconclusive:
                // 探针目标全被拦：退回校内探测，别把"网络好好的"误判成断线
                return await CampusLiveness().probe(interface: interface, server: server, dns: campusDNS)
            }
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
            verboseAuthLogging: config.verboseAuthLogging,
            preferWired: config.link != "jluWiFi",
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
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
        onlineWatchTask?.cancel()
        onlineWatchTask = nil
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
        // 先把网卡列表刷新到"当下"，否则拔线后缓存里还留着 en7，
        // connect() 的守卫会放行，随后又拿一个已经不存在的接口去建通道。
        refreshDiagnostics()
        FileLogger.shared.log("重试：接口数=\(interfaces.count)，状态=\(state)")
        disconnect()
        connect()
    }

    /// 在线巡检：保活还回着、但外网已经不通的情况（真机上见过）也得能发现。
    ///
    /// 每 25 秒走一次真实 204 探针：
    /// - 204：正常；
    /// - 被门户拦下（302/200 门户页）：会话没了 → 连续两次就重新认证；
    /// - 完全探不到：只记日志（可能只是探测目标被拦，不轻易判死刑）。
    private func startOnlineWatch() {
        onlineWatchTask?.cancel()
        onlineWatchTask = Task { @MainActor [weak self] in
            var intercepted = 0
            var silent = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                guard self.state.isOnline else { return }
                let interface = self.interfaces.first { $0.name == self.config.interfaceLock }
                    ?? self.interfaces.first(where: \.isUsableForAuthentication)
                guard let interface else { continue }
                var servers: [IPv4Address] = []
                if let dns = self.config.currentProfile?.dns.compactMap(IPv4Address.init).first {
                    servers.append(dns)
                }
                servers.append(contentsOf: ConnectivityProbe.fallbackDNSServers)
                let probe = ConnectivityProbe(targets: [.cn204, .cloudflare, .gstatic],
                                              timeout: .seconds(2))
                let outcome = await probe.run(interface: interface, dnsServers: servers)
                if Task.isCancelled || !self.state.isOnline { return }
                // 保活停了？超过 120 秒没收到网关应答就认为通道哑了（睡眠/定时器被挂起等）
                if let last = self.lastTrafficAt, Date().timeIntervalSince(last) > 120 {
                    FileLogger.shared.log("在线巡检：保活已 \(Int(Date().timeIntervalSince(last))) 秒没有应答，主动重连")
                    self.recentLog.insert("保活停了，正在重新认证", at: 0)
                    self.lastTrafficAt = nil
                    self.retry()
                    return
                }

                switch SessionLiveness.verdict(outcome) {
                case .online:
                    intercepted = 0
                    silent = 0
                case .offline:
                    intercepted += 1
                    silent = 0
                    FileLogger.shared.log("在线巡检：外网被门户拦下（第 \(intercepted) 次）")
                    if intercepted >= 2 {
                        self.recentLog.insert("外网断了（会话已失效），正在自动重连", at: 0)
                        FileLogger.shared.log("在线巡检：连续 \(intercepted) 次被拦，重新认证")
                        self.retry()
                        return
                    }
                case .inconclusive:
                    intercepted = 0
                    silent += 1
                    FileLogger.shared.log("在线巡检：探针不通（第 \(silent) 次）")
                    // 有些网关掉线时不再重定向到门户，只是静默丢包：探针一直"说不准"。
                    // 连续 4 次（约 100 秒）外网探不到、而校内还通，就按会话失效处理。
                    // 5 分钟冷却，避免探测目标本身被拦时反复重登。
                    if silent >= 4 {
                        let campus = await CampusLiveness().probe(
                            interface: interface,
                            server: IPv4Address(self.config.server) ?? IPv4Address("10.100.61.3")!,
                            dns: self.config.currentProfile?.dns.compactMap(IPv4Address.init).first)
                        let cooledDown = self.lastForcedReauthAt
                            .map { Date().timeIntervalSince($0) > 300 } ?? true
                        if campus, cooledDown {
                            self.lastForcedReauthAt = Date()
                            self.recentLog.insert("外网探不到、校内可达：按会话失效自动重连", at: 0)
                            FileLogger.shared.log("在线巡检：连续 \(silent) 次探不到外网、校内可达 → 重新认证")
                            self.retry()
                            return
                        }
                        silent = 0
                    }
                }
            }
        }
    }

    /// 掉线后自己重连：用户不用盯着面板点「登录」。
    ///
    /// 只在网络类失败（超时、网关无应答、通道异常）上重试；密码错、MAC 不符、
    /// 端口被占这些重试也没用，交给用户处理。最多 6 次，之后停下来等手动操作。
    private func scheduleAutoReconnect(after error: DrcomError) {
        guard config.autoConnect else { return }
        guard ReconnectPolicy.shouldAutoReconnect(error, attempt: autoReconnectAttempt) else {
            if autoReconnectAttempt > 0 {
                FileLogger.shared.log("掉线自动重连：已重试 \(autoReconnectAttempt) 次，暂停等用户处理")
            }
            return
        }
        autoReconnectAttempt += 1
        let attempt = autoReconnectAttempt
        autoReconnectTask?.cancel()
        autoReconnectTask = Task { @MainActor in
            try? await Task.sleep(for: ReconnectPolicy.delay(attempt: attempt))
            guard !Task.isCancelled else { return }
            guard case .failed = state else { return }
            FileLogger.shared.log("掉线自动重连：第 \(attempt) 次（\(error.userMessage)）")
            recentLog.insert("掉线了，正在自动重连（第 \(attempt) 次）", at: 0)
            retry()
        }
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
        // 只关向导 + 刷新诊断。**不在这里创建新窗口**：
        // 之前在同一个动作里关窗口又开窗口，真机上会闪退（AppKit 重入）。
        showWizard = false
        refreshDiagnostics()
    }

    // MARK: 连接结果窗（点完成/登录后立刻给反馈）

    /// 点「完成」或「登录」之后立刻弹出来，显示进度与结果——不把错误藏在菜单栏里。
    func presentConnectionStatus() {
        show(.status)
    }

    func closeConnectionStatus() {
        panel = .main
    }

    // MARK: 网络体检

    func runInspection() {
        guard !inspectionRunning else { return }
        inspectionRunning = true
        FileLogger.shared.log("体检：开始")
        Task { @MainActor in
            let service = InspectionService()
            self.inspectionTimings = [:]

            var started = ContinuousClock.now
            let ips = await service.publicIPs()
            self.inspection.publicIPs = ips
            self.inspectionTimings["ip"] = Self.elapsedMilliseconds(since: started)

            started = ContinuousClock.now
            self.inspection.cloudflare = await service.cloudflareTrace()
            self.inspectionTimings["cloudflare"] = Self.elapsedMilliseconds(since: started)

            started = ContinuousClock.now
            self.inspection.webRTC = await service.webRTC()
            self.inspectionTimings["webrtc"] = Self.elapsedMilliseconds(since: started)

            started = ContinuousClock.now
            self.inspection.dns = await service.dnsLeak()
            self.inspectionTimings["dns"] = Self.elapsedMilliseconds(since: started)

            started = ContinuousClock.now
            self.inspection.captcha = await service.captchaChecks()
            self.inspectionTimings["captcha"] = Self.elapsedMilliseconds(since: started)

            // 顺手把「能不能上网」也跑了（合并成一次检测）
            started = ContinuousClock.now
            await self.runReachabilityInline()
            self.inspectionTimings["reach"] = Self.elapsedMilliseconds(since: started)
            if self.inspection.cloudflare?.ip != nil {
                await self.refreshReputation()
            }
            self.inspectionRunning = false
            FileLogger.shared.log("体检：完成，出口 \(ips.first?.ip ?? "-")")
            // 体检顺带把带宽也测了（只测一次；重试按钮会重新跑）
            if self.speedResults.isEmpty, !self.speedRunning {
                self.runSpeedAll()
            }
        }
    }

    // MARK: 网页认证（面板内）

    /// 由 `PanelPortalBrowser` 调用：切到登录面板并把续体挂起来。
    func presentPortalLogin(_ url: URL, continuation: CheckedContinuation<PortalLoginResult, Never>) {
        portalLoginContinuation = continuation
        pendingPortalLoginURL = url
        show(.portalLogin)
    }

    func finishPortalLogin(_ result: PortalLoginResult) {
        let continuation = portalLoginContinuation
        portalLoginContinuation = nil
        pendingPortalLoginURL = nil
        if panel == .portalLogin { panel = .main }
        FileLogger.shared.log("网页认证面板：用户选择 \(result)")
        continuation?.resume(returning: result)
    }

    // MARK: 校园网门户（App 内查看，不自动弹）

    var portalViewerURL: URL? {
        config.portal.entryURL.flatMap(URL.init(string:))
            ?? config.portal.lastKnownURL.flatMap(URL.init(string:))
    }

    func presentPortalViewer() {
        show(.portal)
    }

    /// 一键看"今天的校园广告/门户"：
    /// 1. 已有入口（上次被门户拦下时记的）→ 直接开；
    /// 2. 没有 → 现场发一次 captive 探测，从 302 的 Location 拿到门户地址；
    /// 3. 探测不到（已在线，学校不会再弹）→ 明确告诉用户，而不是开个空面板。
    var campusAdStatus: String?

    func openCampusAd() {
        if let url = portalViewerURL {
            NSWorkspace.shared.open(url)
            campusAdStatus = Copy.t("B512")
            return
        }
        campusAdStatus = Copy.t("B513")
        Task { @MainActor in
            let interface = interfaces.first {
                $0.isUp && (!$0.isWireless || $0.ipv4 != nil)
            } ?? interfaces.first ?? InterfaceSnapshot(name: "en0", index: 0, ipv4: nil,
                                                       mac: nil, isWireless: false, isUp: true)
            let fetcher = URLSessionPortalFetcher()
            let candidates = ["http://connectivitycheck.gstatic.com/generate_204",
                              "http://www.msftconnecttest.com/connecttest.txt"]
            for candidate in candidates {
                guard let probeURL = URL(string: candidate),
                      let page = try? await fetcher.fetch(probeURL, interface: interface) else { continue }
                if let location = page.location,
                   let url = URL(string: location, relativeTo: probeURL)?.absoluteURL {
                    rememberPortalEntry(url)
                    NSWorkspace.shared.open(url)
                    campusAdStatus = "已打开门户：\(url.host ?? "")"
                    return
                }
            }
            campusAdStatus = "没探测到门户——已经在线时学校不会再弹广告页；" 
                + "被弹过的话，下次会记下地址。"
        }
    }

    func closePortalViewer() {
        panel = .main
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

    // MARK: 设置面板

    func presentSettings() {
        show(.settings)
    }

    func closeSettings() {
        panel = .main
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

    /// 自动模式下的有效锁定：旧版本可能把锁留在无线网卡上，
    /// 只要现在插着有线（且真的有线网卡在），就忽略这个旧锁定——否则"自动"永远是无线。
    /// 当前"正在用"的网口：用户锁定（或自动认卡选中的）优先，其次到服务器的路由出口
    var activeInterfaceName: String? {
        config.interfaceLock ?? routeInterfaceName
    }

    /// 到认证服务器实际走哪块网口（refreshDiagnostics 时更新）
    var routeInterfaceName: String?

    /// 界面里显示的网口顺序：正在用的在前，其次有线优先
    var orderedInterfaces: [InterfaceSnapshot] {
        InterfaceOrdering.sorted(interfaces, active: activeInterfaceName)
    }

    var effectiveInterfaceLock: String? {
        guard let lock = config.interfaceLock, config.link == "auto" else { return config.interfaceLock }
        guard let locked = interfaces.first(where: { $0.name == lock }), locked.isWireless else { return lock }
        let wiredUp = interfaces.filter {
            !$0.isWireless && $0.isUp && !$0.isLoopback
                && !VirtualInterfaceNames.isVirtual($0.name)
        }
        guard !wiredUp.isEmpty else { return lock }
        FileLogger.shared.log("自动：忽略旧的无线锁定 \(lock)，改为优先有线（\(wiredUp.map(\.name).joined(separator: "、"))）")
        return nil
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

    /// 当前该用哪块网卡的"出厂 MAC"（学校登记的就是它）
    func hardwareMACForCurrentInterface() -> String? {
        let usable = interfaceCandidates
        let chosen = activeInterfaceName.flatMap { name in usable.first { $0.name == name } }
            ?? usable.first { $0.ipv4 != nil }
            ?? usable.first
        return chosen?.macForAuthentication
    }

    func parameterSuggestionForCurrentInterface() -> NetworkParameterSuggestion {
        // 不能随便拿"第一块能用的网卡"——那多半是 Wi‑Fi。
        // 顺序：正在用的 → 有线且有地址 → 任一块有地址 → 第一块。
        let usable = interfaces.filter(\.isUsableForAuthentication)
        let interface = activeInterfaceName.flatMap { name in usable.first { $0.name == name } }
            ?? usable.first { !$0.isWireless }
            ?? usable.first
            ?? interfaces.first
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
        show(.detail)
        Task { @MainActor in refreshNetworkDetail() }
    }

    func closeNetworkDetail() {
        panel = .main
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
                results.append(PingSummary(host: Copy.t("B515") + pair.viaDefault.host,
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
        // 闪退时用户往往只发诊断文件：把崩溃栈尾部一起带上
        let crashLog = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JLUGate/crash-stack.log")
        if let data = try? Data(contentsOf: crashLog),
           let content = String(data: data, encoding: .utf8) {
            let tail = content.split(separator: "\n").suffix(40).joined(separator: "\n")
            text += "\n\n== 崩溃日志（最后 40 行）==\n" + tail
        }
        return text
    }

    // MARK: 诊断

    /// 枚举网卡/路由要起 `ifconfig` / `networksetup` 子进程。个别机器上（VPN、
    /// 虚拟网卡多）这些命令会卡住不返回，所以**绝不能放在启动路径或主线程上**：
    /// 主线程一卡，菜单栏图标和面板就永远出不来——用户看到的就是"双击没反应、
    /// 退也退不掉"。启动和被动监测都走后台，只有"点重试/进向导"这种必须当场
    /// 拿到最新网卡的路径才用同步版（并带 4 秒上限）。
    nonisolated private static func computeDiagnostics(server: String)
        -> (interfaces: [InterfaceSnapshot], route: RouteInfo?) {
        let provider = SystemInterfaceProvider()
        let interfaces = provider.physicalInterfaces()
        guard let address = IPv4Address(server) else { return (interfaces, nil) }
        return (interfaces, provider.route(to: address))
    }

    /// 启动时：后台算，算完回主线程更新，不阻塞启动。
    private func scheduleInitialDiagnostics() {
        let server = config.server
        Task { @MainActor [weak self] in
            let started = ContinuousClock.now
            let result = await Task.detached(priority: .utility) {
                Self.computeDiagnostics(server: server)
            }.value
            guard let self, self.config.server == server else { return }
            self.applyDiagnostics(result)
            FileLogger.shared.log("诊断：后台完成，用时 \(started.duration(to: .now))")
        }
    }

    /// 被动监测循环：同样走后台，别让主线程等子进程。
    private func refreshDiagnosticsAsync() async {
        let server = config.server
        let result = await Task.detached(priority: .utility) {
            Self.computeDiagnostics(server: server)
        }.value
        guard config.server == server else { return }
        applyDiagnostics(result)
    }

    /// 同步版：重试/向导/设置里需要立刻拿到网卡列表，但最多等 4 秒。
    func refreshDiagnostics() {
        let server = config.server
        let box = DiagnosticsResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.result = Self.computeDiagnostics(server: server)
            done.signal()
        }
        if done.wait(timeout: .now() + 4) == .timedOut {
            FileLogger.shared.log("诊断：同步刷新超时 4s，先沿用上次结果")
            return
        }
        guard let result = box.result, config.server == server else { return }
        applyDiagnostics(result)
    }

    private func applyDiagnostics(_ result: (interfaces: [InterfaceSnapshot], route: RouteInfo?)) {
        interfaces = result.interfaces
        guard IPv4Address(config.server) != nil else {
            routeSummary = Copy.t("B511")
            routeGuarantee = .noRoute
            return
        }
        if let route = result.route {
            routeInterfaceName = route.interface
            routeSummary = "\(config.server) → \(route.interface ?? "?")（网关 \(route.gateway ?? "-")）"
                + (route.isTunnel ? "  ⚠️ 被代理接管" : "")
        } else {
            routeSummary = "拿不到 \(config.server) 的路由"
        }
        if let chosen = interfaces.first(where: { $0.ipv4 != nil })
            ?? interfaces.first {
            routeGuarantee = RouteGuard(registeredGateway: config.currentProfile?.gateway)
                .evaluate(route: result.route, interface: chosen,
                          helperAuthorized: config.routeGuard.helperAuthorized == true)
        }
    }

    // MARK: 事件

    private func handle(_ event: AuthCoordinator.Event) async {
        FileLogger.shared.log("event \(event)")
        switch event {
        case .state(let next):
            if state != next {
                FileLogger.shared.log("状态：\(state) → \(next)")
            }
            state = next
            switch next {
            case .online:
                lastOnlineAt = Date()
                // 连上了就把"自动重连"计数清零，下次掉线重新从 3s 开始等
                autoReconnectAttempt = 0
                autoReconnectTask?.cancel()
                autoReconnectTask = nil
                startOnlineWatch()
                if portHeldByOfficialClient { onlineViaOfficialClient = true }
                // 在线期间别被 App Nap 挂起（不然 10s 心跳会被延迟成几十秒）
                activityKeeper.begin()
                Notifier.resetDeduplication()
                markSuccessfulLogin()
            case .idle, .failed:
                activityKeeper.end()
                onlineWatchTask?.cancel()
                onlineWatchTask = nil
            default:
                break
            }
            if case .failed(let error) = next {
                lastError = error
                // 服务器说账号/密码不对：清掉保存的密码并请用户重新输入，
                // 否则会拿着同一个错密码一直重试（真机上就这样"怎么点都失败"）。
                if error.isCredentialRejection {
                    // 注意：ldap auth error 不等于"密码错"——同一密码也可能因为
                    // 账号在别处在线 / 服务器忙而偶发。所以**不清密码**，只标记未验证 + 给重输入口。
                    credentialRejectedAt = Date()
                    CredentialStore.markUnverified(account: config.account)
                    if passwordSource != .typed { passwordSource = .savedStale }
                    // 清空内存里的密码，让向导显示"用已保存 / 重新输入"的选择，
                    // 而不是把一个看不出真假的旧密码填在点号里（这正是之前反复失败的原因之一）
                    password = ""
                    requirePasswordReentry = true
                    recentLog.insert("服务器拒绝了凭据（错误码 0x15）。在吉大网络里这通常表示密码不正确——请点「重新输入密码」。", at: 0)
                    FileLogger.shared.log("凭据被拒（保留已保存密码），已提示用户")
                }
                // 有线插着但没填静态参数：直接打开向导的网络参数页，而不是丢一句"连接失败"
                if case .interfaceHasNoIPv4(let interfaceName) = error {
                    wizardNotice = Copy.f("B516", interfaceName)
                    presentWizard()
                    wizardStartsAtNetwork = true
                }
                if case .officialClientRunning = error { portHeldByOfficialClient = true }
                if case .localPortInUse = error { portHeldByOfficialClient = true }
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
                    if portHeldByOfficialClient { onlineViaOfficialClient = true }
                    markSuccessfulLogin()
                    recentLog.insert("认证没有明确成功，但网络实际可用：按已连接处理（服务器原话：\(error.userMessage)）", at: 0)
                    FileLogger.shared.log("probe healthy after failure -> online; server said: \(error.userMessage)")
                }
                scheduleAutoReconnect(after: error)
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
                CredentialStore.markVerified(account: account)
                requirePasswordReentry = false
                self.passwordSource = .savedVerified
                self.clientIP = clientIP
                sessionNumber = session
                recentLog.insert("登录成功：\(account) @ \(clientIP ?? "-")", at: 0)
            case .traffic(let seconds, let stats):
                secondsOnline = seconds
                trafficStats = stats
                lastTrafficAt = Date()
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
    /// 连续探测失败次数：单次抖动不把界面打红（真机上出现过一两次失败就变红）
    private var probeFailStreak = 0

    func probeReachable() async -> Bool {
        let interface = interfaces.first { $0.name == config.interfaceLock }
            ?? interfaces.first(where: \.isUsableForAuthentication)
            ?? interfaces.first
        guard let interface else { return false }
        // 先走 UDP DNS 探针（快），失败再补一次 HTTP：
        // 代理把 UDP 接管掉时 DNS 探针会失败，但网络其实是通的。
        let outcome = await ConnectivityProbe(targets: [.cn204, .cloudflare, .gstatic])
            .run(interface: interface, dnsServers: ConnectivityProbe.fallbackDNSServers)
        if case .healthy = outcome {
            probeFailStreak = 0
            lastHealthyProbeAt = Date()
            return true
        }
        if await httpReachable() {
            probeFailStreak = 0
            lastHealthyProbeAt = Date()
            return true
        }
        probeFailStreak += 1
        // 连续 2 次失败才记"失败时间"；一次抖动不改变结论
        if probeFailStreak >= 2 {
            lastFailedProbeAt = Date()
        }
        return false
    }

    /// 走默认路由的一次轻量 HTTP 检查（代理下也能通）。
    /// 真的能上网才算。
    ///
    /// 以前是"状态码 < 500 就算通"——被门户拦下时 URLSession 会跟到 login.jlu.edu.cn，
    /// 最后拿到的也是 200，于是"会话没了"被当成"网络可达"，永远不会重登。
    private func httpReachable() async -> Bool {
        // 明文 204 必须真的是 204：200/3xx 都说明被门户拦了
        if await statusCode(of: "http://connect.rom.miui.com/generate_204") == 204 {
            return true
        }
        // HTTPS 能完成 TLS 且正常返回，才算真的通（门户拦截/证书替换都会失败）
        if let code = await statusCode(of: "https://www.baidu.com/"), (200..<400).contains(code) {
            return true
        }
        return false
    }

    private func statusCode(of urlString: String) async -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
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

/// 同步刷新诊断时用来跨线程带结果的小盒子（信号量保证可见性）。
private final class DiagnosticsResultBox: @unchecked Sendable {
    var result: (interfaces: [InterfaceSnapshot], route: RouteInfo?)?
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
