import Foundation
import Testing
@testable import JLUGateCore

@Suite("退避（§8.4）")
struct BackoffTests {
    let backoff = Backoff()

    @Test("指数曲线：min(60, 2×2^attempt)")
    func curve() {
        #expect(backoff.baseDelay(attempt: 1) == 4)
        #expect(backoff.baseDelay(attempt: 2) == 8)
        #expect(backoff.baseDelay(attempt: 3) == 16)
        #expect(backoff.baseDelay(attempt: 4) == 32)
        #expect(backoff.baseDelay(attempt: 5) == 60)
        #expect(backoff.baseDelay(attempt: 6) == 60)
        #expect(backoff.baseDelay(attempt: 99) == 60, "指数必须夹到上限，不能溢出")
    }

    @Test("抖动只在 0…jitter 之间，上界永远 ≤ 63 秒")
    func jitterBounds() {
        for attempt in 1...10 {
            let low = backoff.delay(attempt: attempt, jitterFraction: 0)
            let high = backoff.delay(attempt: attempt, jitterFraction: 1)
            let lowSeconds = Double(low.components.seconds)
            let highSeconds = Double(high.components.seconds)
            #expect(abs(lowSeconds - backoff.baseDelay(attempt: attempt)) < 0.001)
            #expect(abs(highSeconds - (backoff.baseDelay(attempt: attempt) + 3)) < 0.001)
            #expect(highSeconds <= 63)
        }
    }

    @Test("抖动分数超出 0…1 会被夹住")
    func jitterClamped() {
        #expect(backoff.delay(attempt: 1, jitterFraction: 5) == backoff.delay(attempt: 1, jitterFraction: 1))
        #expect(backoff.delay(attempt: 1, jitterFraction: -5) == backoff.delay(attempt: 1, jitterFraction: 0))
    }

    @Test("超过 8 次就该交回用户，禁止无限重登")
    func giveUp() {
        #expect(backoff.shouldGiveUp(attempt: 8) == false)
        #expect(backoff.shouldGiveUp(attempt: 9) == true)
    }
}

@Suite("状态机（§7）")
struct SessionStateTests {
    @Test("主路径：idle → discovering → challenging → authenticating → online")
    func happyPath() {
        let path: [AuthState] = [.idle, .discovering, .challenging, .authenticating, .online]
        for (from, to) in zip(path, path.dropFirst()) {
            #expect(from.canTransition(to: to), "\(from.phase) → \(to.phase) 应当合法")
        }
    }

    @Test("掉线与重连")
    func reconnectPaths() {
        #expect(AuthState.online.canTransition(to: .reconnecting(attempt: 1)))
        #expect(AuthState.reconnecting(attempt: 1).canTransition(to: .discovering))
        #expect(AuthState.challenging.canTransition(to: .reconnecting(attempt: 1)))
        #expect(AuthState.reconnecting(attempt: 2).canTransition(to: .idle))
    }

    @Test("任何状态都能进 failed，也能手动回到 idle")
    func alwaysEscapable() {
        let states: [AuthState] = [.idle, .discovering, .challenging, .authenticating, .online,
                                   .reconnecting(attempt: 3)]
        for state in states {
            #expect(state.canTransition(to: .failed(.accountInUse(reason: "账号在别处登录"))))
            #expect(state.canTransition(to: .idle))
        }
    }

    @Test("非法转移必须被拒绝")
    func illegalTransitions() {
        // 注意：`idle → online` 是合法的 —— 协调器探针看到 204 时"本来就在线"，
        // 不走认证直接置 online（见 AuthCoordinator.alreadyOnline）。
        #expect(AuthState.idle.canTransition(to: .online) == true)
        #expect(AuthState.challenging.canTransition(to: .authenticating))
        #expect(AuthState.challenging.canTransition(to: .online) == false)
        // `online → authenticating` 与 `authenticating → discovering` 是 Portal 链路要用的：
        // 204 探针失败后需要重新登录 / 重新探测（PLAN §7.1 的状态子集）。
        #expect(AuthState.online.canTransition(to: .authenticating) == true)
        #expect(AuthState.authenticating.canTransition(to: .discovering) == true)
        #expect(AuthState.discovering.canTransition(to: .idle) == true)
    }

    @Test("failed 之后可以重新开始（用户改完凭据/网卡）")
    func recoverFromFailed() {
        let failed = AuthState.failed(.dhcpAssigned(interface: "en7"))
        #expect(failed.canTransition(to: .discovering))
        #expect(failed.phase == "failed")
    }
}

@Suite("错误分类（§8）")
struct DrcomErrorTests {
    @Test("服务器原文一律照抄，不翻译")
    func serverText() {
        let reasons = ["ldap auth error", "账号在别处登录", "另一台设备已经占用该MAC"]
        for reason in reasons {
            let error = DrcomError.classifyRejection(reason)
            #expect(error.userMessage == reason)
        }
    }

    @Test("账号冲突与 MAC 冲突要分开，且都不自动重试")
    func classification() {
        #expect(DrcomError.classifyRejection("账号在别处登录") == .accountInUse(reason: "账号在别处登录"))
        #expect(DrcomError.classifyRejection("另一台设备已经占用该MAC") == .macInUse(reason: "另一台设备已经占用该MAC"))
        #expect(DrcomError.classifyRejection("ldap auth error") == .rejected(reason: "ldap auth error"))
        // MAC 相关要拆成"被占用"与"登记不符"两种，别混成一句
        #expect(DrcomError.classifyRejection("该MAC已被另一台设备占用")
                == .macInUse(reason: "该MAC已被另一台设备占用"))
        #expect(DrcomError.classifyRejection("MAC地址与登记不符")
                == .macRejected(reason: "MAC地址与登记不符"))
        #expect(DrcomError.classifyRejection("mac not match")
                == .macRejected(reason: "mac not match"))

        for error in [DrcomError.accountInUse(reason: "x"), .macInUse(reason: "y"), .rejected(reason: "z")] {
            #expect(error.isRetryable == false)
        }
    }

    @Test("拔网线 / 网卡没地址 → 等网络变化，而不是退避空转")
    func awaitsPathChangeClassification() {
        #expect(DrcomError.adapterUnplugged(interface: "en7").awaitsPathChange)
        #expect(DrcomError.interfaceHasNoIPv4(interface: "en7").awaitsPathChange)
        #expect(DrcomError.gatewayUnreachable(host: "192.0.2.1").awaitsPathChange == false)
        #expect(DrcomError.accountInUse(reason: "x").awaitsPathChange == false)
    }

    @Test("账号冲突必须等用户，不能自己循环")
    func accountInUseRequiresUser() {
        #expect(DrcomError.accountInUse(reason: "x").requiresUserAction)
        #expect(DrcomError.macInUse(reason: "y").requiresUserAction)
        #expect(DrcomError.dhcpAssigned(interface: "en7").requiresUserAction)
        #expect(DrcomError.gatewayUnreachable(host: "10.100.61.3").requiresUserAction == false)
    }

    @Test("每类错误都有面向用户的一句话，且不重复笼统说法")
    func messagesAreSpecific() {
        let errors: [DrcomError] = [
            .macMismatch(expected: "02:00:00:00:00:01", actual: "aa:bb:cc:dd:ee:ff"),
            .interfaceHasNoIPv4(interface: "en7"),
            .adapterUnplugged(interface: "en7"),
            .dhcpAssigned(interface: "en7"),
            .staticConfigMismatch(field: "IP", expected: "192.0.2.10", actual: "192.168.1.5"),
            .gatewayUnreachable(host: "10.100.61.3"),
            .capturedByTunnel(interface: "utun4"),
            .officialClientRunning(process: "drcomauth", pid: 686),
            .localPortInUse(port: 61440, process: "surge"),
            .accountInUse(reason: "账号在别处登录"),
            .macInUse(reason: "另一台设备已经占用该MAC"),
            .rejected(reason: "ldap auth error"),
        ]
        let messages = errors.map(\.userMessage)
        #expect(Set(messages).count == messages.count)
        #expect(messages.contains { $0.contains("61440") })
        #expect(messages.contains { $0.contains("utun4") })
    }
}
