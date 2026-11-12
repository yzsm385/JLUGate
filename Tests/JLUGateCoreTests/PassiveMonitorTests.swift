import Foundation
import Testing
@testable import JLUGateCore

@Suite("被动观测模式（已经在线就别逼人输密码）")
struct PassiveMonitorTests {
    @Test("204 通过 → 直接报在线")
    func online() {
        #expect(PassiveMonitor.decide(.online) == .reportOnline)
    }

    @Test("被门户拦住 → 才要账号密码")
    func needsAuth() {
        #expect(PassiveMonitor.decide(.needsAuthentication(statusCode: 302, location: "http://p/login"))
                == .requestCredentials)
        #expect(PassiveMonitor.decide(.needsAuthentication(statusCode: 200, location: nil))
                == .requestCredentials)
    }

    @Test("链路不通 → 报失败原因，不弹向导")
    func unreachable() {
        #expect(PassiveMonitor.decide(.unreachable(reason: "全部超时"))
                == .reportOffline("全部超时"))
    }

    @Test("自动弹向导只弹一次")
    func promptOnlyOnce() {
        #expect(PassiveMonitor.shouldPromptOnNeedsAuth(wasOnline: true, alreadyPrompted: false))
        #expect(PassiveMonitor.shouldPromptOnNeedsAuth(wasOnline: false, alreadyPrompted: false))
        #expect(PassiveMonitor.shouldPromptOnNeedsAuth(wasOnline: true, alreadyPrompted: true) == false)
    }
}

// MARK: - TLS 通道被切断（2026-11-12）

@Suite("TLS 被切断必须和「没网」分开")
struct PassiveMonitorTLSBlockedTests {
    @Test("tlsBlocked 不判离线，而是标注出来")
    func tlsBlockedIsNotOffline() {
        let decision = PassiveMonitor.decide(.tlsBlocked(reason: "github.com EOF"))
        guard case .reportTLSBlocked(let reason) = decision else {
            Issue.record("期望 reportTLSBlocked，实际 \(decision)")
            return
        }
        #expect(reason == "github.com EOF")
    }

    @Test("unreachable 仍然是 reportOffline，两者不能混")
    func unreachableStaysOffline() {
        let decision = PassiveMonitor.decide(.unreachable(reason: "全超时"))
        guard case .reportOffline = decision else {
            Issue.record("期望 reportOffline，实际 \(decision)")
            return
        }
    }
}

