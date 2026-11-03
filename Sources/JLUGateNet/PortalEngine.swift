import Foundation
import Synchronization
import JLUGateCore

/// 探针的最小抽象，方便单测注入假探针。
public protocol ConnectivityProbing: Sendable {
    func run(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome
}

extension ConnectivityProbe: ConnectivityProbing {}

public struct PortalConfiguration: Sendable {
    public var credentials: PortalCredentials?
    public var autoFill: Bool
    public var silentRetryOnce: Bool
    public var silentRetryDelay: Duration
    /// 弹窗频率上限（PLAN §5.4.3：1 次 / 5 分钟）。
    public var promptCooldown: Duration
    public var probeInterval: Duration
    public var failTolerance: Int
    public var dnsServers: [IPv4Address]
    public var backoff: Backoff
    /// 认证成功后等 204 的轮询次数与间隔。
    public var successChecks: Int

    public init(credentials: PortalCredentials? = nil,
                autoFill: Bool = true,
                silentRetryOnce: Bool = true,
                silentRetryDelay: Duration = .seconds(1),
                promptCooldown: Duration = .seconds(300),
                probeInterval: Duration = .seconds(30),
                failTolerance: Int = 2,
                dnsServers: [IPv4Address] = [],
                backoff: Backoff = Backoff(),
                successChecks: Int = 5) {
        self.credentials = credentials
        self.autoFill = autoFill
        self.silentRetryOnce = silentRetryOnce
        self.silentRetryDelay = silentRetryDelay
        self.promptCooldown = promptCooldown
        self.probeInterval = probeInterval
        self.failTolerance = failTolerance
        self.dnsServers = dnsServers
        self.backoff = backoff
        self.successChecks = successChecks
    }
}

/// `JLU.WIFI` 的网页认证链路。
///
/// 与 Dr.Com 的唯一共同点是"都要先选对物理网卡"（PLAN §5.4）：
/// 没有 61440、没有摘要、没有心跳，在线判定全靠 204 探针。
///
/// 认证本身交给 `WKWebView`（`PortalBrowser`），程序**不碰明文密码**，
/// 也就自然免疫"页面改版 / JS 加密 / 验证码"（PLAN §5.4.2）。
public actor PortalEngine: AuthProvider {
    public nonisolated let link: AccessLink = .jluWiFi

    public enum Event: Sendable, Equatable {
        case state(AuthState)
        case entry(URL)
        case note(String)
        case online
        case needsUser
    }

    private let probe: any ConnectivityProbing
    private let browser: any PortalBrowser
    private let detector: PortalDetector
    private let configuration: PortalConfiguration
    private let clock: any Clock
    private let hub = AuthStateHub()

    private var eventContinuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var epoch: UInt64 = 0
    private var task: Task<Void, Never>?
    private var authState: AuthState = .idle
    private var currentEntry: URL?
    private var lastPromptAt: ContinuousClock.Instant?

    public init(probe: any ConnectivityProbing = ConnectivityProbe(),
                browser: any PortalBrowser,
                detector: PortalDetector = PortalDetector(),
                configuration: PortalConfiguration = PortalConfiguration(),
                clock: any Clock = SystemClock()) {
        self.probe = probe
        self.browser = browser
        self.detector = detector
        self.configuration = configuration
        self.clock = clock
    }

    // MARK: AuthProvider

    public nonisolated var state: AsyncStream<AuthState> { hub.makeStream() }

    public func start(using snapshot: InterfaceSnapshot) async {
        await stop()
        let epoch = nextEpoch()
        task = Task { [weak self] in
            await self?.run(epoch: epoch, interface: snapshot)
        }
    }

    /// 停止链路。**不删 Cookie**：下次还能靠它静默恢复（PLAN §5.4.3）。
    public func stop() async {
        _ = nextEpoch()
        task?.cancel()
        task = nil
        setState(.idle)
    }

    /// 用户主动"退出登录"才清 Cookie。
    public func logout() async {
        await stop()
        await browser.clearCookies()
        currentEntry = nil
    }

    // MARK: 用户动作

    /// 菜单里的"打开 Portal 登录页"。
    public func requestLogin() async {
        guard let url = currentEntry else {
            emit(.note("还没有拿到门户地址：请先让程序探测一次（或到设置里填入口 URL）"))
            return
        }
        _ = await presentLogin(url: url)
    }

    public func pendingEntry() -> URL? { currentEntry }

    public func currentState() -> AuthState { authState }

    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    // MARK: 状态机

    private func run(epoch: UInt64, interface: InterfaceSnapshot) async {
        var attempt = 0
        while isCurrent(epoch) && !Task.isCancelled {
            setState(.discovering)
            let outcome = await probe.run(interface: interface, dnsServers: configuration.dnsServers)
            guard isCurrent(epoch) else { return }

            switch outcome {
            case .healthy:
                attempt = 0
                markOnline()
                do {
                    try await monitor(epoch: epoch, interface: interface)
                } catch {
                    // 掉线（或 stop），回到循环重新探测
                }
            case .captivePortal:
                attempt = 0
                guard let entry = await detector.detect(probe: outcome, interface: interface) else {
                    emit(.note("被门户拦下，但没解析出入口地址"))
                    try? await sleepUnlessCurrent(epoch, configuration.probeInterval)
                    continue
                }
                currentEntry = entry.url
                emit(.entry(entry.url))
                emit(.note("门户入口（\(entry.source.rawValue)）：\(entry.url.absoluteString)"))

                // 先试一次"Cookie 还在"的静默路径（PLAN §5.4.3）
                if configuration.silentRetryOnce {
                    try? await clock.sleep(for: configuration.silentRetryDelay)
                    let again = await probe.run(interface: interface,
                                                dnsServers: configuration.dnsServers)
                    guard isCurrent(epoch) else { return }
                    if again == .healthy {
                        markOnline()
                        try? await monitor(epoch: epoch, interface: interface)
                        continue
                    }
                }

                setState(.authenticating)
                emit(.needsUser)

                // 弹窗节流：冷却期内不重复打断用户
                if let last = lastPromptAt,
                   clock.now() - last < configuration.promptCooldown {
                    emit(.note("登录弹窗冷却中（\(configuration.promptCooldown)），稍后自动重试"))
                    try? await sleepUnlessCurrent(epoch, configuration.promptCooldown)
                    continue
                }

                let result = await presentLogin(url: entry.url)
                guard isCurrent(epoch) else { return }
                switch result {
                case .succeeded:
                    if await waitForOnline(epoch: epoch, interface: interface) {
                        markOnline()
                        do { try await monitor(epoch: epoch, interface: interface) } catch {}
                    } else {
                        emit(.note("登录页显示成功，但 204 探针仍未通过"))
                        setState(.failed(.rejected(reason: "网页登录后仍无法访问外网")))
                        return
                    }
                case .cancelled:
                    emit(.note("用户取消了网页登录"))
                    setState(.idle)
                    return
                case .failed(let reason):
                    setState(.failed(.rejected(reason: reason)))
                    return
                }
            case .unreachable(let reason):
                attempt += 1
                if configuration.backoff.shouldGiveUp(attempt: attempt) {
                    setState(.failed(.notCampusNetwork(detail: reason)))
                    return
                }
                setState(.reconnecting(attempt: attempt))
                do {
                    try await clock.sleep(for: configuration.backoff.delay(attempt: attempt))
                } catch {
                    return
                }
            }
        }
    }

    /// 在线监控：204 连续失败 `failTolerance` 次就回去重新判定。
    private func monitor(epoch: UInt64, interface: InterfaceSnapshot) async throws {
        var failures = 0
        while isCurrent(epoch) && !Task.isCancelled {
            try await clock.sleep(for: configuration.probeInterval)
            let outcome = await probe.run(interface: interface, dnsServers: configuration.dnsServers)
            guard isCurrent(epoch) else { throw DrcomError.cancelled }
            if outcome.isOnline {
                failures = 0
                continue
            }
            failures += 1
            if failures >= configuration.failTolerance {
                setState(previous: .online, next: .authenticating)
                emit(.note("204 探针连续 \(failures) 次失败，需要重新登录"))
                return
            }
        }
        throw DrcomError.cancelled
    }

    private func waitForOnline(epoch: UInt64, interface: InterfaceSnapshot) async -> Bool {
        for _ in 0..<configuration.successChecks {
            guard isCurrent(epoch) else { return false }
            let outcome = await probe.run(interface: interface, dnsServers: configuration.dnsServers)
            if outcome.isOnline { return true }
            try? await clock.sleep(for: .seconds(1))
        }
        return false
    }

    private func presentLogin(url: URL) async -> PortalLoginResult {
        lastPromptAt = clock.now()
        let credentials = configuration.autoFill ? configuration.credentials : nil
        let result = await browser.presentLogin(url: url, credentials: credentials)
        if case .succeeded = result {
            emit(.note("网页登录流程返回成功"))
        }
        return result
    }

    // MARK: 工具

    private func markOnline() {
        setState(previous: authState, next: .online)
        emit(.online)
    }

    private func setState(previous: AuthState, next: AuthState) {
        guard next != authState else { return }
        if !previous.canTransition(to: next) {
            emit(.note("非法状态转移 \(previous.phase) → \(next.phase)（已阻止）"))
            return
        }
        authState = next
        hub.publish(next)
        emit(.state(next))
    }

    private func setState(_ next: AuthState) {
        setState(previous: authState, next: next)
    }

    private func sleepUnlessCurrent(_ epoch: UInt64, _ duration: Duration) async throws {
        guard isCurrent(epoch) else { throw DrcomError.cancelled }
        try await clock.sleep(for: duration)
    }

    private func emit(_ event: Event) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        eventContinuations[id] = nil
    }

    private func nextEpoch() -> UInt64 {
        epoch &+= 1
        return epoch
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        epoch == value
    }
}

/// 让协调器能把"打开登录页"转发给 Portal 链路。
public protocol PortalLoginControlling: Sendable {
    func requestLogin() async
    func pendingEntry() async -> URL?
}

extension PortalEngine: PortalLoginControlling {}
