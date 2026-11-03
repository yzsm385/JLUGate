import Foundation
import Testing
@testable import JLUGateCore

@Suite("字段解释 / 吞吐量 / Ping 统计")
struct NetworkInsightTests {
    @Test("关键术语都有白话解释，且不重复 id")
    func fieldGuideCoverage() {
        for id in ["interface", "mac", "ipv4", "mask", "gateway", "dns", "route", "tun", "speed", "ping"] {
            #expect(FieldGuide.explanation(for: id)?.isEmpty == false, "缺少 \(id) 的解释")
        }
        let ids = FieldGuide.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        // MAC 的解释要点出"学校按 MAC 登记"这件事
        #expect(FieldGuide.explanation(for: "mac")?.contains("登记") == true)
        #expect(FieldGuide.explanation(for: "tun")?.contains("10.0.0.0/8") == true)
    }

    @Test("吞吐量：字节/秒 → Mbps，并换算成 MB/s")
    func throughput() {
        // 10 MB 用了 8 秒 = 80 Mbit / 8 s = 10 Mbps
        #expect(abs(Throughput.megabitsPerSecond(bytes: 10_000_000, seconds: 8) - 10) < 0.001)
        #expect(Throughput.format(megabitsPerSecond: 10) == "10.0 Mbps（≈ 1.2 MB/s）")
        #expect(Throughput.format(megabitsPerSecond: 0) == "—")
        #expect(Throughput.megabitsPerSecond(bytes: 0, seconds: 1) == 0)
        #expect(Throughput.megabitsPerSecond(bytes: 100, seconds: 0) == 0, "零时长不能除零")
    }

    @Test("Ping 统计：平均/最小/最大/丢包")
    func pingSummary() {
        let summary = PingSummary(host: "1.1.1.1", latencies: [10, 20, 30], attempted: 4)
        #expect(summary.average == 20)
        #expect(summary.minimum == 10)
        #expect(summary.maximum == 30)
        #expect(summary.loss == 0.25)
        #expect(summary.description.contains("平均 20 ms"))
        #expect(summary.description.contains("丢包 25%"))
    }

    @Test("全部超时时给的是全部超时，不是 NaN")
    func pingAllLost() {
        let summary = PingSummary(host: "10.0.0.1", latencies: [], attempted: 3)
        #expect(summary.average == nil)
        #expect(summary.loss == 1)
        #expect(summary.description.contains("全部超时"))
    }
}
