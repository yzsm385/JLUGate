import Foundation
import Testing
import JLUGateCore
@testable import JLUGateNet

// MARK: - 假 provider

final class FakeAuthProvider: AuthProvider, SessionTelemetryProviding, @unchecked Sendable {
    let link: AccessLink
    private let hub = AuthStateHub()
    private let telemetryHub = AuthTelemetryHub()
    private let box = Atomic<[String]>([])

    init(link: AccessLink) {
        self.link = link
    }

    var calls: [String] { box.withLock { $0 } }
    var state: AsyncStream<AuthState> { hub.makeStream() }

    func start(using snapshot: InterfaceSnapshot) async {
        box.withLock { $0.append("start:\(snapshot.name)") }
        hub.publish(.discovering)
    }

    func stop() async {
        box.withLock { $0.append("stop") }
        hub.publish(.idle)
    }

    func emit(_ state: AuthState) {
        hub.publish(state)
    }

    var telemetry: AsyncStream<AuthTelemetry> { telemetryHub.makeStream() }

    func emitTelemetry(_ event: AuthTelemetry) {
        telemetryHub.publish(event)
    }
}

/// 记录 makeProvider 被怎么调用，并保留实例供断言。
final class ProviderSpy: @unchecked Sendable {
    private let box = Atomic<[(AccessLink, String)]>([])
    private let providers = Atomic<[FakeAuthProvider]>([])

    func make(link: AccessLink, snapshot: InterfaceSnapshot) -> any AuthProvider {
        box.withLock { $0.append((link, snapshot.name)) }
        let provider = FakeAuthProvider(link: link)
        providers.withLock { $0.append(provider) }
        return provider
    }

    var requests: [(AccessLink, String)] { box.withLock { $0 } }
    var last: FakeAuthProvider? { providers.withLock { $0.last } }
    var count: Int { providers.withLock { $0.count } }
}

// MARK: - 假探测器

struct FakeLinkDetector: LinkDetector {
    var drcomReachable: Bool
    var outcome: ProbeOutcome = .unreachable(reason: "无探针")
    var probeCalls = Atomic<[String]>([])

    func probeDrcom(interface: InterfaceSnapshot, server: IPv4Endpoint,
                    localPort: UInt16, timeout: Duration) async -> Bool {
        probeCalls.withLock { $0.append("drcom:\(interface.name)") }
        return drcomReachable
    }

    func probeConnectivity(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome {
        probeCalls.withLock { $0.append("http:\(interface.name)") }
        return outcome
    }
}

@MainActor
@Suite("AuthCoordinator 选链路（§5.4.4）")
struct AuthCoordinatorTests {

    private let wired = InterfaceSnapshot(name: "en7", index: 12, ipv4: "192.0.2.10",
                                          mac: "02:00:00:00:00:01", isWireless: false, isUp: true)
    private let wifi = InterfaceSnapshot(name: "en0", index: 4, ipv4: "192.0.2.20",
                                         mac: "02:00:00:00:00:02", isWireless: true, isUp: true)

    private func makeCoordinator(preference: LinkPreference = .auto,
                                 autoDetect: Bool = true,
                                 interfaces: [InterfaceSnapshot]? = nil,
                                 registeredMAC: String? = nil,
                                 strictMACCheck: Bool = false,
                                 detector: FakeLinkDetector,
                                 spy: ProviderSpy) -> AuthCoordinator {
        let provider = FakeInterfaceProvider(
            interfaces: interfaces ?? [wired],
            route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7"),
            configMethod: "Manual",
            gateway: "192.0.2.1")
        let configuration = AuthCoordinator.Configuration(
            preference: preference,
            autoDetect: autoDetect,
            server: IPv4Endpoint(host: IPv4Address("10.100.61.3")!, port: 61440),
            localPort: 61440,
            registeredMAC: registeredMAC.flatMap(MACAddress.init),
            dnsServers: [IPv4Address("10.10.10.10")!],
            probeTimeout: .seconds(1),
            strictMACCheck: strictMACCheck)
        return AuthCoordinator(configuration: configuration,
                               interfaces: provider,
                               detector: detector,
                               makeProvider: { link, snapshot in spy.make(link: link, snapshot: snapshot) })
    }

    private func collect(_ coordinator: AuthCoordinator,
                         until predicate: @escaping @Sendable (AuthCoordinator.Event) -> Bool,
                         timeout: Duration = .seconds(2)) async throws -> [AuthCoordinator.Event] {
        let stream = await coordinator.events()
        var events: [AuthCoordinator.Event] = []
        let collector = Task {
            for await event in stream {
                events.append(event)
                if predicate(event) { break }
            }
        }
        try await Task.sleep(for: timeout)
        collector.cancel()
        return events
    }

    @Test("自动：UDP challenge 有回执 → 有线 Dr.Com，且只探测一次")
    func autoPicksDrcom() async throws {
        let spy = ProviderSpy()
        let detector = FakeLinkDetector(drcomReachable: true)
        let coordinator = makeCoordinator(detector: detector, spy: spy)
        await coordinator.start()

        #expect(await coordinator.currentLink() == .wired)
        #expect(spy.requests.count == 1)
        #expect(spy.requests.first?.0 == .wired)
        #expect(spy.last?.calls.first == "start:en7")
        #expect(detector.probeCalls.withLock { $0 } == ["drcom:en7"],
                "探测只发一个 challenge、不重试，也不该再跑 204 探针")
        await coordinator.stop()
    }

    @Test("无线口探测成功 → 认成 JLU.PC，而不是有线")
    func autoPicksJluPC() async throws {
        let spy = ProviderSpy()
        let coordinator = makeCoordinator(interfaces: [wifi],
                                          detector: FakeLinkDetector(drcomReachable: true),
                                          spy: spy)
        await coordinator.start()
        #expect(await coordinator.currentLink() == .jluPC)
        await coordinator.stop()
    }

    @Test("UDP 不通 + 204 被拦 → 走 JLU.WIFI（Portal）")
    func autoFallsBackToPortal() async throws {
        let spy = ProviderSpy()
        var detector = FakeLinkDetector(drcomReachable: false)
        detector.outcome = .captivePortal(statusCode: 302, location: "http://10.100.61.3/login")
        let coordinator = makeCoordinator(detector: detector, spy: spy)
        await coordinator.start()
        #expect(await coordinator.currentLink() == .jluWiFi)
        #expect(detector.probeCalls.withLock { $0 } == ["drcom:en7", "http:en7"])
        await coordinator.stop()
    }

    @Test("UDP 不通但 204 已通 → 直接 online，不建任何 provider")
    func alreadyOnline() async throws {
        let spy = ProviderSpy()
        var detector = FakeLinkDetector(drcomReachable: false)
        detector.outcome = .healthy
        let coordinator = makeCoordinator(detector: detector, spy: spy)
        await coordinator.start()
        #expect(await coordinator.currentState() == .online)
        #expect(spy.count == 0, "已经在线上就不该再拉起认证")
        await coordinator.stop()
    }

    @Test("两个探针都不通 + 有线手动配置 → 仍按有线 Dr.Com 试一次（全局代理场景）")
    func bothProbesDownButWiredManualStillTries() async throws {
        let spy = ProviderSpy()
        var detector = FakeLinkDetector(drcomReachable: false)
        detector.outcome = .unreachable(reason: "全部超时")
        let coordinator = makeCoordinator(detector: detector, spy: spy)
        await coordinator.start()

        // 以前这里直接 failed(.notCampusNetwork)：全局代理把探针包吞掉时，
        // 用户就表现为「断线后在全局模式下怎么都连不回来」。
        #expect(await coordinator.currentLink() == .wired)
        #expect(spy.count == 1)
        await coordinator.stop()
    }

    @Test("两个探针都不通 + 无线 → failed(.notCampusNetwork)，不建 provider")
    func notCampus() async throws {
        let spy = ProviderSpy()
        var detector = FakeLinkDetector(drcomReachable: false)
        detector.outcome = .unreachable(reason: "全部超时")
        let coordinator = makeCoordinator(interfaces: [wifi], detector: detector, spy: spy)
        await coordinator.start()

        guard case .failed(let error) = await coordinator.currentState() else {
            Issue.record("应为 failed，实际 \(await coordinator.currentState())")
            return
        }
        #expect(error == .notCampusNetwork(detail: "全部超时"))
        #expect(spy.count == 0)
        await coordinator.stop()
    }

    @Test("用户显式指定有线：即使探测不通也照用（不擅自改成 Portal）")
    func forcedLinkWins() async throws {
        let spy = ProviderSpy()
        var detector = FakeLinkDetector(drcomReachable: false)
        detector.outcome = .captivePortal(statusCode: 302, location: nil)
        let coordinator = makeCoordinator(preference: .wired, detector: detector, spy: spy)
        await coordinator.start()
        #expect(await coordinator.currentLink() == .wired)
        #expect(detector.probeCalls.withLock { $0 }.isEmpty, "用户指定了链路就不该再去探测")
        await coordinator.stop()
    }

    @Test("关掉自动探测：不碰校园网关，只跑 204 探针")
    func autoDetectDisabled() async throws {
        let spy = ProviderSpy()
        var detector = FakeLinkDetector(drcomReachable: true)
        detector.outcome = .healthy
        let coordinator = makeCoordinator(autoDetect: false, detector: detector, spy: spy)
        await coordinator.start()
        #expect(detector.probeCalls.withLock { $0 } == ["http:en7"])
        #expect(await coordinator.currentState() == .online)
        await coordinator.stop()
    }

    @Test("严格模式：MAC 不匹配才 failed(.macMismatch)，不选口、不探测")
    func macMismatch() async throws {
        let spy = ProviderSpy()
        let detector = FakeLinkDetector(drcomReachable: true)
        let coordinator = makeCoordinator(registeredMAC: "02:00:00:00:00:09",
                                          strictMACCheck: true,
                                          detector: detector, spy: spy)
        await coordinator.start()

        guard case .failed(let error) = await coordinator.currentState() else {
            Issue.record("应为 failed")
            return
        }
        #expect(error == .macMismatch(expected: "02:00:00:00:00:09", actual: "02:00:00:00:00:01"))
        #expect(detector.probeCalls.withLock { $0 }.isEmpty)
        #expect(spy.count == 0)
        await coordinator.stop()
    }

    @Test("切换/停止时必须 teardown 旧 provider（不许双活）")
    func stopTearsDownProvider() async throws {
        let spy = ProviderSpy()
        let coordinator = makeCoordinator(detector: FakeLinkDetector(drcomReachable: true), spy: spy)
        await coordinator.start()
        let provider = try #require(spy.last)
        #expect(await coordinator.currentLink() == .wired)

        await coordinator.stop()
        #expect(provider.calls.contains("stop"), "旧 provider 必须收到 stop")
        #expect(await coordinator.currentState() == .idle)
        #expect(await coordinator.currentLink() == nil)

        // 再启动会建新的 provider（而不是复用旧的）
        await coordinator.start()
        #expect(spy.count == 2)
        #expect(await coordinator.currentLink() == .wired)
        await coordinator.stop()
    }

    @Test("保活遥测（流量/会话）会经协调器转给 UI")
    func forwardsTelemetry() async throws {
        let spy = ProviderSpy()
        let coordinator = makeCoordinator(detector: FakeLinkDetector(drcomReachable: true), spy: spy)
        let stream = await coordinator.events()
        let received = Atomic<[AuthCoordinator.Event]>([])
        let collector = Task {
            for await event in stream {
                if case .telemetry = event { received.withLock { $0.append(event) } }
            }
        }
        await coordinator.start()
        let provider = try #require(spy.last)
        provider.emitTelemetry(.traffic(secondsOnline: 42, stats: [732, 42, 0, 0, 1, 2]))
        provider.emitTelemetry(.session(account: "20230001", clientIP: "192.0.2.10", session: 0x631D))

        try await expectEventually("收到两条遥测", timeout: .seconds(2)) {
            received.withLock { $0.count } >= 2
        }
        collector.cancel()
        let events = received.withLock { $0 }
        #expect(events.contains(.telemetry(.traffic(secondsOnline: 42, stats: [732, 42, 0, 0, 1, 2]))))
        #expect(events.contains(.telemetry(.session(account: "20230001", clientIP: "192.0.2.10", session: 0x631D))))
        await coordinator.stop()
    }

    @Test("provider 的状态会透传给协调器订阅者")
    func forwardsProviderState() async throws {
        let spy = ProviderSpy()
        let coordinator = makeCoordinator(detector: FakeLinkDetector(drcomReachable: true), spy: spy)
        let stream = await coordinator.events()
        await coordinator.start()
        let provider = try #require(spy.last)
        // 合法路径：discovering（start 时已发）→ challenging → authenticating → online
        provider.emit(.challenging)
        provider.emit(.authenticating)
        provider.emit(.online)

        let sawOnline = Atomic(false)
        let collector = Task {
            for await event in stream {
                if case .state(.online) = event { sawOnline.withLock { $0 = true }; break }
            }
        }
        try await expectEventually("协调器看到 online", timeout: .seconds(2)) {
            sawOnline.withLock { $0 }
        }
        collector.cancel()
        #expect(await coordinator.currentState() == .online)
        await coordinator.stop()
    }
}
