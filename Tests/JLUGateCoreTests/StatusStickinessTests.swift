import Foundation
import Testing
@testable import JLUGateCore

@Suite("状态粘性（最后一次探测说了算）")
struct StatusStickinessTests {
    private let now = Date()

    @Test("最后探测成功 → 引擎失败也保持在线")
    func healthyWins() {
        let sticky = StatusStickiness(lastHealthyProbeAt: now.addingTimeInterval(-30))
        #expect(sticky.shouldStayOnline(now: now))
    }

    @Test("最后探测失败 → 允许变红")
    func failureWins() {
        let sticky = StatusStickiness(lastHealthyProbeAt: now.addingTimeInterval(-60),
                                      lastFailedProbeAt: now.addingTimeInterval(-5))
        #expect(!sticky.shouldStayOnline(now: now))
    }

    @Test("先失败后成功 → 以成功为准")
    func recovered() {
        let sticky = StatusStickiness(lastHealthyProbeAt: now.addingTimeInterval(-5),
                                      lastFailedProbeAt: now.addingTimeInterval(-30))
        #expect(sticky.shouldStayOnline(now: now))
    }

    @Test("很久没有探测结果 → 不再坚持")
    func stale() {
        let sticky = StatusStickiness(lastHealthyProbeAt: now.addingTimeInterval(-900))
        #expect(!sticky.shouldStayOnline(now: now))
    }

    @Test("从未探测成功 → 不坚持")
    func never() {
        #expect(!StatusStickiness().shouldStayOnline(now: now))
    }
}
