import Foundation
import Synchronization
import JLUGateCore

/// 三种接入链路（PLAN §4）。
public enum AccessLink: String, Sendable, CaseIterable {
    /// Dr.Com UDP，静态公网 IP
    case wired
    /// Dr.Com UDP，`JLU.PC` 无线（共用同一份地址档案）
    case jluPC
    /// HTTP 网页认证（Portal）
    case jluWiFi

    public var displayName: String {
        switch self {
        case .wired: "有线"
        case .jluPC: "JLU.PC"
        case .jluWiFi: "JLU.WIFI"
        }
    }

    public var usesDrcomUDP: Bool {
        self != .jluWiFi
    }
}

/// 用户在设置里选的那一档（`auto` 不是一种链路，而是"让程序自己挑"）。
public enum LinkPreference: String, Sendable, CaseIterable {
    case auto
    case wired
    case jluPC
    case jluWiFi

    public var forcedLink: AccessLink? {
        switch self {
        case .auto: nil
        case .wired: .wired
        case .jluPC: .jluPC
        case .jluWiFi: .jluWiFi
        }
    }
}

/// 两条链路对外的唯一抽象（签名取自 PLAN §4）：协调器只依赖这个，UI 只依赖 `AuthState`。
public protocol AuthProvider: AnyObject, Sendable {
    var link: AccessLink { get }
    func start(using snapshot: InterfaceSnapshot) async
    func stop() async
    var state: AsyncStream<AuthState> { get }
}

// MARK: - 遥测（保活流量等 UI 需要的信息）

public enum AuthTelemetry: Sendable, Equatable {
    case session(account: String, clientIP: String?, session: UInt16)
    case traffic(secondsOnline: UInt32, stats: [UInt32])
    case note(String)
}

public protocol SessionTelemetryProviding: Sendable {
    var telemetry: AsyncStream<AuthTelemetry> { get }
}

// MARK: - 状态广播

/// 把 provider 的内部事件收敛成"当前状态 + 订阅"。
final class AuthStateHub: @unchecked Sendable {
    private struct HubState: Sendable {
        var latest: AuthState = .idle
        var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]
    }

    private let state = Mutex(HubState())

    func publish(_ next: AuthState) {
        let continuations = state.withLock { state -> [AsyncStream<AuthState>.Continuation] in
            state.latest = next
            return Array(state.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(next)
        }
    }

    func makeStream() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            let id = UUID()
            let latest = state.withLock { state -> AuthState in
                state.continuations[id] = continuation
                return state.latest
            }
            continuation.yield(latest)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations[id] = nil }
            }
        }
    }
}

// MARK: - Dr.Com provider

/// 把 `DrcomEngine` 包成 `AuthProvider`。
/// 引擎自己是 actor，`state` 用一次广播转成 `AsyncStream<AuthState>`。
public final class DrcomAuthProvider: AuthProvider, SessionTelemetryProviding, @unchecked Sendable {
    public let link: AccessLink
    public let engine: DrcomEngine
    private let hub = AuthStateHub()
    private let telemetryHub = AuthTelemetryHub()
    private let relay: Task<Void, Never>

    public init(engine: DrcomEngine, link: AccessLink) {
        self.engine = engine
        self.link = link
        let hub = self.hub
        let telemetryHub = self.telemetryHub
        relay = Task {
            let events = await engine.events()
            for await event in events {
                switch event {
                case .state(let state):
                    hub.publish(state)
                case .session(let account, let clientIP, let session):
                    telemetryHub.publish(.session(account: account, clientIP: clientIP, session: session))
                case .traffic(let secondsOnline, let stats):
                    telemetryHub.publish(.traffic(secondsOnline: secondsOnline, stats: stats))
                case .log(let message):
                    telemetryHub.publish(.note(message))
                }
            }
        }
        // 引擎的当前状态先补一发，避免订阅者错过
        Task { [hub, engine] in
            hub.publish(await engine.currentState())
        }
    }

    deinit {
        relay.cancel()
    }

    public var state: AsyncStream<AuthState> { hub.makeStream() }

    /// 引擎会自己按 MAC 重新解析接口（比外部塞进来的快照更可靠，见 PLAN §6.3），
    /// 这里只把快照当作一次诊断信息。
    public func start(using snapshot: InterfaceSnapshot) async {
        await engine.start()
    }

    public func stop() async {
        await engine.stop()
        relay.cancel()
    }

    public var telemetry: AsyncStream<AuthTelemetry> { telemetryHub.makeStream() }

    /// 让 UI 能"打开 Portal 登录页"时读到当前入口（Dr.Com 链路没有）。
    public func pendingPortalEntry() async -> URL? { nil }
}

/// 遥测广播（与 `AuthStateHub` 同构，只是载荷不同）。
final class AuthTelemetryHub: @unchecked Sendable {
    private let state = Mutex<[UUID: AsyncStream<AuthTelemetry>.Continuation]>([:])

    func publish(_ event: AuthTelemetry) {
        for continuation in state.withLock({ Array($0.values) }) {
            continuation.yield(event)
        }
    }

    func makeStream() -> AsyncStream<AuthTelemetry> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0[id] = nil }
            }
        }
    }
}

// MARK: - 链路探测

public protocol LinkDetector: Sendable {
    /// 发**一个** challenge，`timeout` 内有回执即认为在认证网络（PLAN §5.4.4：只发 1 个、不重试）。
    func probeDrcom(interface: InterfaceSnapshot, server: IPv4Endpoint,
                    localPort: UInt16, timeout: Duration) async -> Bool
    func probeConnectivity(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome
}

public struct DefaultLinkDetector: LinkDetector {
    public var codec: DrcomCodec
    public var probe: ConnectivityProbe
    public var channelFactory: any ChannelFactory

    public init(codec: DrcomCodec = DrcomCodec(),
                probe: ConnectivityProbe = ConnectivityProbe(),
                channelFactory: any ChannelFactory = BSDChannelFactory()) {
        self.codec = codec
        self.probe = probe
        self.channelFactory = channelFactory
    }

    public func probeDrcom(interface: InterfaceSnapshot, server: IPv4Endpoint,
                           localPort: UInt16, timeout: Duration) async -> Bool {
        guard let localIP = interface.ipv4Address else { return false }
        let channel = channelFactory.makeChannel()
        defer { Task { await channel.close() } }
        do {
            try await channel.open(localIP: localIP, localPort: localPort,
                                   remote: server, interfaceIndex: interface.index)
            let challenge = try codec.makeChallenge(serial: UInt16.random(in: .min ... .max),
                                                    subtype: PacketLayout.Challenge.firstSubtype)
            try await channel.send(challenge)
            _ = try await channel.receive(timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    public func probeConnectivity(interface: InterfaceSnapshot,
                                  dnsServers: [IPv4Address]) async -> ProbeOutcome {
        await probe.run(interface: interface, dnsServers: dnsServers)
    }
}

// MARK: - 协调器

/// 同时只持有一个活跃 provider；切换链路前必须 teardown（否则会出现"Portal 已登录、UDP 还在保活"）。
public actor AuthCoordinator {
    public enum Event: Sendable, Equatable {
        case link(AccessLink)
        case state(AuthState)
        case note(String)
        case telemetry(AuthTelemetry)
    }

    public struct Configuration: Sendable {
        public var preference: LinkPreference
        public var autoDetect: Bool
        public var server: IPv4Endpoint
        public var localPort: UInt16
        public var registeredMAC: MACAddress?
        public var interfaceLock: String?
        /// 探针用的学校 DNS（**不要**用系统 DNS）。
        public var dnsServers: [IPv4Address]
        public var probeTimeout: Duration

        public init(preference: LinkPreference = .auto,
                    autoDetect: Bool = true,
                    server: IPv4Endpoint = IPv4Endpoint(host: PacketLayout.defaultServer,
                                                       port: PacketLayout.serverPort),
                    localPort: UInt16 = PacketLayout.localPort,
                    registeredMAC: MACAddress? = nil,
                    interfaceLock: String? = nil,
                    dnsServers: [IPv4Address] = [],
                    probeTimeout: Duration = .seconds(3)) {
            self.preference = preference
            self.autoDetect = autoDetect
            self.server = server
            self.localPort = localPort
            self.registeredMAC = registeredMAC
            self.interfaceLock = interfaceLock
            self.dnsServers = dnsServers
            self.probeTimeout = probeTimeout
        }
    }

    private let configuration: Configuration
    private let interfaces: any InterfaceProvider
    private let detector: any LinkDetector
    private let makeProvider: @Sendable (AccessLink, InterfaceSnapshot) -> any AuthProvider

    private var provider: (any AuthProvider)?
    private var providerRelay: Task<Void, Never>?
    private var telemetryRelay: Task<Void, Never>?
    private var hub: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var activeLink: AccessLink?
    private var state: AuthState = .idle
    private var epoch: UInt64 = 0

    public init(configuration: Configuration,
                interfaces: any InterfaceProvider = SystemInterfaceProvider(),
                detector: any LinkDetector = DefaultLinkDetector(),
                makeProvider: @escaping @Sendable (AccessLink, InterfaceSnapshot) -> any AuthProvider) {
        self.configuration = configuration
        self.interfaces = interfaces
        self.detector = detector
        self.makeProvider = makeProvider
    }

    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            hub[id] = continuation
            if let link = activeLink { continuation.yield(.link(link)) }
            continuation.yield(.state(state))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func currentLink() -> AccessLink? { activeLink }
    public func currentState() -> AuthState { state }

    // MARK: 生命周期

    public func start() async {
        await stop()
        let epoch = nextEpoch()
        do {
            let resolution = try await resolve()
            guard isCurrent(epoch) else { return }

            switch resolution {
            case .alreadyOnline:
                emit(.note("204 探针已通过：当前已在线上，无需认证"))
                setState(.online, epoch: epoch)
            case .provider(let link, let snapshot):
                emit(.link(link))
                activeLink = link
                let provider = makeProvider(link, snapshot)
                self.provider = provider
                subscribe(to: provider)
                emit(.note("已选择链路：\(link.displayName)（接口 \(snapshot.name)）"))
                await provider.start(using: snapshot)
            }
        } catch let error as DrcomError {
            guard isCurrent(epoch) else { return }
            setState(.failed(error), epoch: epoch)
        } catch {
            guard isCurrent(epoch) else { return }
            setState(.failed(.channelFailure("\(error)")), epoch: epoch)
        }
    }

    public func stop() async {
        _ = nextEpoch()
        providerRelay?.cancel()
        providerRelay = nil
        telemetryRelay?.cancel()
        telemetryRelay = nil
        if let provider {
            await provider.stop()
        }
        provider = nil
        activeLink = nil
        setStateInternal(.idle)
    }

    // MARK: 选择

    private enum Resolution {
        case alreadyOnline
        case provider(AccessLink, InterfaceSnapshot)
    }

    private func resolve() async throws -> Resolution {
        var candidates = interfaces.physicalInterfaces()
        if let lock = configuration.interfaceLock {
            candidates = candidates.filter { $0.name == lock }
        }
        guard !candidates.isEmpty else {
            throw DrcomError.adapterUnplugged(interface: configuration.interfaceLock ?? "en*")
        }

        let chosen = try pick(from: candidates)

        if let forced = configuration.preference.forcedLink {
            emit(.note("用户指定链路：\(forced.displayName)"))
            return .provider(forced, chosen)
        }

        if configuration.autoDetect {
            let reachable = await detector.probeDrcom(interface: chosen,
                                                      server: configuration.server,
                                                      localPort: configuration.localPort,
                                                      timeout: configuration.probeTimeout)
            if reachable {
                return .provider(chosen.isWireless ? .jluPC : .wired, chosen)
            }
            emit(.note("UDP challenge 无回执：\(chosen.name) 上可能不是 Dr.Com 网关"))
        }

        let outcome = await detector.probeConnectivity(interface: chosen,
                                                       dnsServers: configuration.dnsServers)
        switch outcome {
        case .healthy:
            return .alreadyOnline
        case .captivePortal(let statusCode, let location):
            emit(.note("204 探针被拦截（HTTP \(statusCode)\(location.map { " → \($0)" } ?? "")），走网页认证"))
            return .provider(.jluWiFi, chosen)
        case .unreachable(let reason):
            throw DrcomError.notCampusNetwork(detail: reason)
        }
    }

    private func pick(from candidates: [InterfaceSnapshot]) throws -> InterfaceSnapshot {
        // 只考虑"真能用来认证"的口：有 IPv4、不是回环、不是虚拟口。
        // 一个都没有时保留原始候选，好让引擎报出 interfaceHasNoIPv4 而不是静默失败。
        let usable = candidates.filter(\.isUsableForAuthentication)
        let pool = usable.isEmpty ? candidates : usable

        if let registered = configuration.registeredMAC {
            let matched = pool.filter { $0.macAddress?.matches(registered) == true }
            guard !matched.isEmpty else {
                throw DrcomError.macMismatch(expected: registered.description,
                                             actual: candidates.first?.mac ?? "无")
            }
            return matched.sorted { lhs, rhs in
                (lhs.isWireless ? 1 : 0, lhs.index) < (rhs.isWireless ? 1 : 0, rhs.index)
            }.first!
        }
        return pool.sorted { lhs, rhs in
            let lscore = (lhs.isWireless ? 0 : 2) + (lhs.ipv4 != nil ? 1 : 0)
            let rscore = (rhs.isWireless ? 0 : 2) + (rhs.ipv4 != nil ? 1 : 0)
            if lscore != rscore { return lscore > rscore }
            return lhs.index < rhs.index
        }.first!
    }

    // MARK: 内部

    private func subscribe(to provider: any AuthProvider) {
        providerRelay?.cancel()
        let stream = provider.state
        providerRelay = Task { [weak self] in
            for await state in stream {
                await self?.applyExternalState(state)
            }
        }

        telemetryRelay?.cancel()
        telemetryRelay = nil
        if let telemetryProvider = provider as? any SessionTelemetryProviding {
            let telemetryStream = telemetryProvider.telemetry
            telemetryRelay = Task { [weak self] in
                for await event in telemetryStream {
                    await self?.forwardTelemetry(event)
                }
            }
        }
    }

    private func forwardTelemetry(_ event: AuthTelemetry) {
        guard provider != nil else { return }
        emit(.telemetry(event))
    }

    /// 菜单里的"打开 Portal 登录页"：只有 Portal 链路认这个动作。
    public func requestPortalLogin() async {
        guard let portal = provider as? any PortalLoginControlling else {
            emit(.note("当前链路不是网页认证，没有登录页可打开"))
            return
        }
        await portal.requestLogin()
    }

    /// 菜单里的"重新抢回在线"。
    public func reclaimPortal() async {
        guard let portal = provider as? any PortalLoginControlling else {
            emit(.note("当前链路不是网页认证"))
            return
        }
        await portal.reclaim()
    }

    public func portalEntry() async -> URL? {
        guard let portal = provider as? any PortalLoginControlling else { return nil }
        return await portal.pendingEntry()
    }

    private func applyExternalState(_ next: AuthState) {
        guard provider != nil else { return }
        setStateInternal(next)
    }

    private func setState(_ next: AuthState, epoch: UInt64) {
        guard isCurrent(epoch) else { return }
        setStateInternal(next)
    }

    private func setStateInternal(_ next: AuthState) {
        guard next != state else { return }
        if !state.canTransition(to: next) {
            emit(.note("非法状态转移 \(state.phase) → \(next.phase)（已阻止）"))
            return
        }
        state = next
        emit(.state(next))
    }

    private func emit(_ event: Event) {
        for continuation in hub.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        hub[id] = nil
    }

    private func nextEpoch() -> UInt64 {
        epoch &+= 1
        return epoch
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        epoch == value
    }
}
