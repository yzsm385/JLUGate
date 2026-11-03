import Foundation
import Testing
import JLUGateCore
@testable import JLUGateNet

// MARK: - 假件

struct ScriptedProbing: ConnectivityProbing {
    private let outcomes: Atomic<[ProbeOutcome]>
    private let fallback: ProbeOutcome
    let calls = Atomic(0)

    init(_ outcomes: [ProbeOutcome], fallback: ProbeOutcome = .captivePortal(statusCode: 302, location: nil)) {
        self.outcomes = Atomic(outcomes)
        self.fallback = fallback
    }

    func run(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome {
        calls.withLock { $0 += 1 }
        return outcomes.withLock { scripted -> ProbeOutcome in
            guard !scripted.isEmpty else { return fallback }
            return scripted.removeFirst()
        }
    }
}

final class FakePortalBrowser: PortalBrowser, @unchecked Sendable {
    private let result: PortalLoginResult
    private let box = Atomic<[(String, PortalCredentials?)]>([])
    private let cleared = Atomic(false)

    init(result: PortalLoginResult) {
        self.result = result
    }

    var presented: [(url: String, credentials: PortalCredentials?)] { box.withLock { $0 } }
    var didClearCookies: Bool { cleared.withLock { $0 } }

    func presentLogin(url: URL, credentials: PortalCredentials?) async -> PortalLoginResult {
        box.withLock { $0.append((url.absoluteString, credentials)) }
        return result
    }

    func clearCookies() async {
        cleared.withLock { $0 = true }
    }
}

struct StubFetcher: PortalPageFetching {
    var page: PortalPage

    func fetch(_ url: URL, interface: InterfaceSnapshot) async throws -> PortalPage {
        page
    }
}

/// 异步断言小工具：等某个条件成立。
func portalExpect(_ description: String, timeout: Duration = .seconds(2),
                  _ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("等待超时：\(description)")
}

// MARK: - 判定

@Suite("PortalDetector（入口解析）")
struct PortalDetectorTests {
    let interface = InterfaceSnapshot(name: "en0", index: 4, ipv4: "192.0.2.20", mac: "02:00:00:00:00:02",
                                      isWireless: true, isUp: true)

    @Test("302 的 Location 就是入口")
    func redirectEntry() async {
        let detector = PortalDetector(fetcher: StubFetcher(page: PortalPage(statusCode: 200, body: "")))
        let entry = await detector.detect(
            probe: .captivePortal(statusCode: 302, location: "http://10.100.61.3/login?x=1"),
            interface: interface)
        #expect(entry?.url.absoluteString == "http://10.100.61.3/login?x=1")
        #expect(entry?.source == .redirect)
    }

    @Test("200 页面里抓 form action")
    func pageFormAction() async {
        let html = """
        <html><body><form method="post" action="/auth/login.do?wlanuserip=192.0.2.20">
        <input name="username"></form></body></html>
        """
        let detector = PortalDetector(fetcher: StubFetcher(page: PortalPage(statusCode: 200, body: html)),
                                      configuredURL: URL(string: "http://10.100.61.3/")!)
        let entry = await detector.detect(probe: .captivePortal(statusCode: 200, location: nil),
                                          interface: interface)
        #expect(entry?.url.absoluteString == "http://10.100.61.3/auth/login.do?wlanuserip=192.0.2.20")
        #expect(entry?.source == .pageInspection)
        #expect(entry?.loginFormAction?.absoluteString == entry?.url.absoluteString)
    }

    @Test("meta refresh 也能当入口")
    func metaRefresh() async {
        let html = "<meta http-equiv=\"refresh\" content=\"0; url=http://portal.example/login\">"
        let detector = PortalDetector(fetcher: StubFetcher(page: PortalPage(statusCode: 200, body: html)),
                                      configuredURL: URL(string: "http://portal.example/")!)
        let entry = await detector.detect(probe: .captivePortal(statusCode: 200, location: nil),
                                          interface: interface)
        #expect(entry?.url.absoluteString == "http://portal.example/login")
    }

    @Test("已经 204 在线时不给入口（不该弹窗）")
    func healthyNoEntry() async {
        let detector = PortalDetector(fetcher: StubFetcher(page: PortalPage(statusCode: 204, body: "")))
        #expect(await detector.detect(probe: .healthy, interface: interface) == nil)
    }

    @Test("没 Location、没表单时回落到配置的入口")
    func fallsBackToConfigured() async {
        let detector = PortalDetector(fetcher: StubFetcher(page: PortalPage(statusCode: 200, body: "<html/>")),
                                      configuredURL: URL(string: "http://10.100.61.3/portal")!)
        let entry = await detector.detect(probe: .captivePortal(statusCode: 200, location: nil),
                                          interface: interface)
        #expect(entry?.url.absoluteString == "http://10.100.61.3/portal")
        #expect(entry?.source == .configured)
    }
}

// MARK: - 引擎

/// 记录状态流，避免"用轮询抓瞬时状态"带来的 flaky。
final class StateRecorder: @unchecked Sendable {
    private let states = Atomic<[AuthState]>([])
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<AuthState>) {
        task = Task { [states] in
            for await state in stream {
                states.withLock { $0.append(state) }
            }
        }
    }

    var all: [AuthState] { states.withLock { $0 } }

    func saw(_ state: AuthState) -> Bool {
        all.contains { $0 == state }
    }

    func sawFailed() -> (any Error)? {
        for state in all {
            if case .failed(let error) = state { return error }
        }
        return nil
    }

    func cancel() { task?.cancel() }
}

@Suite("PortalEngine（§7.1 状态子集）")
struct PortalEngineTests {
    let interface = InterfaceSnapshot(name: "en0", index: 4, ipv4: "192.0.2.20", mac: "02:00:00:00:00:02",
                                      isWireless: true, isUp: true)

    private func makeEngine(probe: ScriptedProbing,
                            browser: FakePortalBrowser,
                            failTolerance: Int = 999) -> PortalEngine {
        let configuration = PortalConfiguration(
            credentials: PortalCredentials(account: "20230001", password: "test-pass-2024"),
            silentRetryOnce: true,
            silentRetryDelay: .milliseconds(1),
            promptCooldown: .seconds(300),
            probeInterval: .seconds(1),
            failTolerance: failTolerance,
            successChecks: 3)
        return PortalEngine(probe: probe, browser: browser,
                            detector: PortalDetector(fetcher: StubFetcher(
                                page: PortalPage(statusCode: 200, body: "<form action='/login'>"))),
                            configuration: configuration,
                            clock: FakeClock())
    }

    @Test("204 已在线：不弹窗，直接 online")
    func alreadyOnline() async throws {
        let browser = FakePortalBrowser(result: .succeeded)
        let engine = makeEngine(probe: ScriptedProbing([.healthy]), browser: browser)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)

        try await portalExpect("进入 online") { recorder.saw(.online) }
        #expect(browser.presented.isEmpty, "已在线不该打断用户")
        recorder.cancel()
        await engine.logout()
    }

    @Test("被拦但 Cookie 仍有效：静默恢复，不弹窗")
    func silentRetrySucceeds() async throws {
        let browser = FakePortalBrowser(result: .succeeded)
        let probe = ScriptedProbing([.captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),
                                     .healthy])
        let engine = makeEngine(probe: probe, browser: browser)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)

        try await portalExpect("静默恢复进入 online") { recorder.saw(.online) }
        #expect(browser.presented.isEmpty)
        recorder.cancel()
        await engine.stop()
    }

    @Test("静默不行 → 弹窗；登录成功且探针通过 → online")
    func promptThenOnline() async throws {
        let browser = FakePortalBrowser(result: .succeeded)
        let probe = ScriptedProbing([
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),
            .healthy
        ])
        let engine = makeEngine(probe: probe, browser: browser)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)

        try await portalExpect("进入 online") { recorder.saw(.online) }
        let presented = browser.presented
        #expect(presented.count == 1)
        #expect(presented.first?.url == "http://10.100.61.3/login")
        #expect(presented.first?.credentials?.account == "20230001", "自动填充要带上账号")
        recorder.cancel()
        await engine.stop()
    }

    @Test("用户取消登录 → 回 idle，不报错")
    func cancelled() async throws {
        let browser = FakePortalBrowser(result: .cancelled)
        let probe = ScriptedProbing([
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login")
        ])
        let engine = makeEngine(probe: probe, browser: browser)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)

        try await portalExpect("回到 idle") { recorder.saw(.idle) }
        #expect(recorder.sawFailed() == nil, "取消不是错误")
        recorder.cancel()
        await engine.stop()
    }

    @Test("登录页报错 → failed，错误串原样保留")
    func loginFailed() async throws {
        let browser = FakePortalBrowser(result: .failed(reason: "用户名或密码错误"))
        let probe = ScriptedProbing([
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login")
        ])
        let engine = makeEngine(probe: probe, browser: browser)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)

        try await portalExpect("进入 failed") { recorder.sawFailed() != nil }
        guard let error = recorder.sawFailed() as? DrcomError else {
            Issue.record("应为 DrcomError")
            return
        }
        #expect(error == .rejected(reason: "用户名或密码错误"))
        #expect(error.userMessage == "用户名或密码错误")
        recorder.cancel()
        await engine.stop()
    }

    @Test("在线状态下探针连续 2 次失败 → 回到 authenticating（要求重新登录）")
    func dropsWhenProbeFails() async throws {
        let browser = FakePortalBrowser(result: .succeeded)
        let probe = ScriptedProbing([
            .healthy,                                                     // detect
            .unreachable(reason: "x"), .unreachable(reason: "x"),          // 监控连续失败 2 次
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),  // 重新 detect
            .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"),  // 静默重试
            .healthy                                                       // 登录后确认
        ])
        let engine = makeEngine(probe: probe, browser: browser, failTolerance: 2)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)

        try await portalExpect("进入 online", timeout: .seconds(3)) { recorder.saw(.online) }
        try await portalExpect("掉线后要求登录", timeout: .seconds(3)) {
            recorder.all.contains { if case .authenticating = $0 { true } else { false } }
        }
        try await portalExpect("弹过一次登录窗", timeout: .seconds(3)) { browser.presented.count == 1 }
        recorder.cancel()
        await engine.stop()
    }

    @Test("stop() 不清 Cookie（下次还要靠它静默恢复）")
    func stopKeepsCookies() async throws {
        let browser = FakePortalBrowser(result: .succeeded)
        let engine = makeEngine(probe: ScriptedProbing([.healthy]), browser: browser)
        let recorder = StateRecorder(engine.state)
        await engine.start(using: interface)
        try await portalExpect("进入 online") { recorder.saw(.online) }
        await engine.stop()
        #expect(browser.didClearCookies == false)

        await engine.logout()
        #expect(browser.didClearCookies == true, "只有主动退出登录才清 Cookie")
        recorder.cancel()
    }
}
