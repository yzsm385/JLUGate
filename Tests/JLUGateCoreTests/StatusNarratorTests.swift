import Foundation
import Testing
@testable import JLUGateCore

@Suite("状态文案（人话 + 比喻）")
struct StatusNarratorTests {
    @Test("在线：明确告诉用户是谁在维持")
    func online() {
        let story = StatusNarrator.story(.online)
        #expect(story.title.contains("已连接"))
        #expect(story.oneLiner.contains("JLU Gate"))
        #expect(story.action == nil)
    }

    @Test("官方客户端占端口但网络是通的：不报错，说明现状")
    func onlineViaOfficialClient() {
        let story = StatusNarrator.story(.onlineViaOfficialClient)
        #expect(story.title.contains("官方客户端"))
        #expect(story.oneLiner.contains("通"))
        #expect(story.action?.contains("退出") == true)
        // 绝不能把内部术语甩给用户
        #expect(!story.oneLiner.contains("UDP"))
        #expect(!story.title.contains("UDP"))
    }

    @Test("端口被占且没网：给可执行动作")
    func portHeldButOffline() {
        let story = StatusNarrator.story(.officialClientHoldingPort)
        #expect(story.action?.contains("退出") == true)
        #expect(!story.oneLiner.contains("UDP"))
    }

    @Test("等待网络：说清是插线/地址问题")
    func waiting() {
        let story = StatusNarrator.story(.waitingForNetwork)
        #expect(story.action?.contains("网线") == true)
    }

    @Test("每条文案都不出现内部术语")
    func noJargon() {
        let jargon = ["UDP", "socket", "bind", "端口 61440", "channel"]
        for phase: StatusPhase in [.idle, .working, .online, .onlineViaOfficialClient,
                                   .officialClientHoldingPort, .waitingForNetwork, .failed] {
            let story = StatusNarrator.story(phase)
            for word in jargon {
                #expect(!story.oneLiner.contains(word), "\(phase) 文案里出现了术语 \(word)")
                #expect(!story.title.contains(word))
            }
        }
    }
}

@Suite("状态粘性（避免灰→绿→红乱跳）")
struct StatusStickinessTests {
    private let now = Date()

    @Test("刚探测通过、刚在线过 → 失败也当在线")
    func sticky() {
        #expect(StatusStickiness.treatFailureAsOnline(
            lastOnlineAt: now.addingTimeInterval(-30),
            lastHealthyProbeAt: now.addingTimeInterval(-5), now: now))
    }

    @Test("探测早就成功了但已经过去很久 → 不算在线")
    func stale() {
        #expect(!StatusStickiness.treatFailureAsOnline(
            lastOnlineAt: now.addingTimeInterval(-600),
            lastHealthyProbeAt: now.addingTimeInterval(-600), now: now))
    }

    @Test("从没在线过，但探测刚通过（官方客户端在管）→ 视为在线")
    func neverOnlineButHealthy() {
        #expect(StatusStickiness.treatFailureAsOnline(
            lastOnlineAt: nil,
            lastHealthyProbeAt: now.addingTimeInterval(-2), now: now))
    }

    @Test("没有探测成功记录 → 不粘")
    func noProbe() {
        #expect(!StatusStickiness.treatFailureAsOnline(
            lastOnlineAt: now.addingTimeInterval(-5), lastHealthyProbeAt: nil, now: now))
    }
}
