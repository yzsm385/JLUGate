import Testing
import Foundation
@testable import JLUGateCore

@Suite("掉线自动重连策略")
struct ReconnectPolicyTests {
    @Test("网络类失败值得自动重试")
    func retriesNetworkErrors() {
        #expect(ReconnectPolicy.shouldAutoReconnect(.timeout(stage: "keepAliveA"), attempt: 0))
        #expect(ReconnectPolicy.shouldAutoReconnect(.gatewayUnreachable(host: "10.100.61.3"), attempt: 0))
        #expect(ReconnectPolicy.shouldAutoReconnect(.channelFailure("EOF"), attempt: 0))
        #expect(ReconnectPolicy.shouldAutoReconnect(.notCampusNetwork(detail: "no reply"), attempt: 0))
    }

    @Test("凭据 / MAC / 端口这类问题不自动重试（重试也没用，交给用户）")
    func noRetryForUserFixableErrors() {
        #expect(!ReconnectPolicy.shouldAutoReconnect(.rejected(reason: "ldap auth error"), attempt: 0))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.macMismatch(expected: "a", actual: "b"), attempt: 0))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.localPortInUse(port: 61440, process: "DrClientNS"), attempt: 0))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.interfaceHasNoIPv4(interface: "en7"), attempt: 0))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.accountInUse(reason: "x"), attempt: 0))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.cancelled, attempt: 0))
    }

    @Test("最多重连 6 次就停下来")
    func stopsAtCap() {
        #expect(ReconnectPolicy.shouldAutoReconnect(.timeout(stage: "x"), attempt: 5))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.timeout(stage: "x"), attempt: 6))
        #expect(!ReconnectPolicy.shouldAutoReconnect(.timeout(stage: "x"), attempt: 99))
    }

    @Test("退避曲线：3 / 6 / 12 / 24，封顶 30 秒")
    func backoffCurve() {
        #expect(ReconnectPolicy.delay(attempt: 1) == .seconds(3))
        #expect(ReconnectPolicy.delay(attempt: 2) == .seconds(6))
        #expect(ReconnectPolicy.delay(attempt: 3) == .seconds(12))
        #expect(ReconnectPolicy.delay(attempt: 4) == .seconds(24))
        #expect(ReconnectPolicy.delay(attempt: 5) == .seconds(30))
        #expect(ReconnectPolicy.delay(attempt: 6) == .seconds(30))
    }
}
