import Foundation
import Observation
import SwiftUI
import JLUGateCore
import JLUGateNet

/// UI 的唯一状态源。所有引擎动作都从这里发起，视图不直接碰 `DrcomEngine`。
@MainActor
@Observable
final class AppModel {
    var config: AppConfig
    var password: String
    var state: AuthState = .idle
    var lastError: DrcomError?
    var clientIP: String?
    var sessionNumber: UInt16?
    var secondsOnline: UInt32 = 0
    var trafficStats: [UInt32] = []
    var recentLog: [String] = []
    var interfaces: [InterfaceSnapshot] = []
    var routeSummary: String = "未检测"

    @ObservationIgnored private var engine: DrcomEngine?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private let interfacesProvider = SystemInterfaceProvider()

    init() {
        let loaded = ConfigStore.load()
        config = loaded
        password = CredentialStore.password(for: loaded.account) ?? ""
        refreshDiagnostics()
        observeSleepWake()
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
        case .discovering: "正在查找网卡…"
        case .challenging: "握手中…"
        case .authenticating: "认证中…"
        case .online: "在线"
        case .reconnecting(let attempt): "重连中（第 \(attempt) 次）"
        case .failed: "未连接"
        }
    }

    var detailLine: String {
        if case .failed(let error) = state { return error.userMessage }
        if let clientIP { return "本机 \(clientIP)" }
        return config.server
    }

    /// 静态参数是否已录（决定要不要弹向导）。`configuredAt` 非空即视为已配置。
    var isConfigured: Bool {
        config.currentProfile?.configuredAt != nil
    }

    // MARK: 动作

    func connect() {
        guard !config.account.isEmpty else {
            state = .failed(.malformed("还没填账号"))
            return
        }
        guard let server = IPv4Address(config.server) else {
            state = .failed(.malformed("服务器地址不合法"))
            return
        }
        if password.isEmpty {
            state = .failed(.malformed("还没填密码"))
            return
        }
        try? CredentialStore.save(password: password, account: config.account)
        ConfigStore.save(config)

        let profile = config.currentProfile
        let configuration = EngineConfiguration(
            account: config.account,
            password: password,
            hostname: SystemHostname.value,
            registeredMAC: profile?.registeredMAC.flatMap(MACAddress.init),
            interfaceLock: config.interfaceLock,
            server: server,
            serverPort: UInt16(config.serverPort),
            localPort: UInt16(config.localPort),
            keepAliveInterval: .seconds(config.keepAlive.interval),
            missTolerance: config.keepAlive.missTolerance)

        let factory: any ChannelFactory = config.channel == "bsd"
            ? BSDChannelFactory()
            : NWChannelFactory()

        let engine = DrcomEngine(configuration: configuration,
                                 channelFactory: factory,
                                 interfaces: interfacesProvider,
                                 clock: SystemClock(),
                                 backoff: Backoff(base: config.backoff.base,
                                                  cap: config.backoff.cap,
                                                  jitter: config.backoff.jitter,
                                                  maxAttempts: config.backoff.maxAttempts))
        self.engine = engine
        engineTask?.cancel()
        engineTask = Task { [weak self] in
            guard let self else { return }
            // 先订阅再启动，避免漏掉 discovering 之前的状态
            let stream = await engine.events()
            await engine.start()
            for await event in stream {
                await self.handle(event)
            }
        }
    }

    func disconnect() {
        engineTask?.cancel()
        engineTask = nil
        let engine = self.engine
        self.engine = nil
        state = .idle
        clientIP = nil
        Task { await engine?.stop() }
    }

    func retry() {
        disconnect()
        connect()
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

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsReport.make(config: config,
                                                              engineState: state,
                                                              interfaces: interfaces), forType: .string)
        recentLog.insert("已复制诊断信息到剪贴板", at: 0)
    }

    func refreshDiagnostics() {
        interfaces = interfacesProvider.physicalInterfaces()
        guard let server = IPv4Address(config.server) else {
            routeSummary = "服务器地址不合法"
            return
        }
        if let route = interfacesProvider.route(to: server) {
            routeSummary = "\(config.server) → \(route.interface ?? "?")（网关 \(route.gateway ?? "-")）"
                + (route.isTunnel ? "  ⚠️ 被代理接管" : "")
        } else {
            routeSummary = "拿不到 \(config.server) 的路由"
        }
    }

    // MARK: 事件

    private func handle(_ event: DrcomEngine.Event) async {
        switch event {
        case .state(let next):
            state = next
            if case .failed(let error) = next { lastError = error }
        case .session(let account, let clientIP, let session):
            self.clientIP = clientIP
            sessionNumber = session
            recentLog.insert("登录成功：\(account) @ \(clientIP ?? "-")", at: 0)
        case .traffic(let seconds, let stats):
            secondsOnline = seconds
            trafficStats = stats
        case .log(let message):
            recentLog.insert(message, at: 0)
            if recentLog.count > 50 { recentLog.removeLast() }
        }
    }

    // MARK: 休眠 / 唤醒（PLAN §8.3）

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recentLog.insert("系统休眠：关通道、停全部定时器（不发 Logout）", at: 0)
                await self.engine?.suspendForSleep()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recentLog.insert("系统唤醒：等待 2s 后重新获取接口并重建 socket", at: 0)
                await self.engine?.resumeAfterWake()
                self.refreshDiagnostics()
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
