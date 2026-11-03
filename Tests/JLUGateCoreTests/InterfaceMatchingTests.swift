import Foundation
import Testing
@testable import JLUGateCore

/// MAC 一律用字节数组构造：仓库里不出现"看起来像真实 MAC"的字面量。
private func mac(_ bytes: [UInt8]) -> String {
    MACAddress(bytes: bytes)!.description
}

@Suite("按 MAC 自动认卡 / 多卡时让用户选")
struct InterfaceMatchingTests {
    private var registered: MACAddress { MACAddress(bytes: [0xBC, 0xFC, 0xE7, 0xF3, 0x5B, 0x55])! }
    private var otherRegistered: MACAddress { MACAddress(bytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])! }

    private var candidates: [InterfaceMACCandidate] {
        [
            // 系统给网卡套了私有 MAC，但出厂 MAC 命中登记值
            InterfaceMACCandidate(name: "en7", ipv4: "192.0.2.10",
                                  currentMAC: mac([0xF2, 0x2F, 0xBC, 0x61, 0x68, 0xE7]),
                                  hardwareMAC: mac([0xBC, 0xFC, 0xE7, 0xF3, 0x5B, 0x55])),
            InterfaceMACCandidate(name: "en2", ipv4: nil,
                                  currentMAC: mac([0x02, 0x00, 0x00, 0x00, 0x00, 0x02]),
                                  hardwareMAC: mac([0x02, 0x00, 0x00, 0x00, 0x00, 0x02])),
            InterfaceMACCandidate(name: "en0", ipv4: "192.0.2.20",
                                  currentMAC: mac([0x02, 0x00, 0x00, 0x00, 0x00, 0x03]),
                                  hardwareMAC: mac([0x02, 0x00, 0x00, 0x00, 0x00, 0x03])),
        ]
    }

    @Test("出厂 MAC 命中就算匹配（私有地址不影响）")
    func matchesOnHardwareMAC() {
        let matched = InterfaceMatching.matchedCandidates(registered: registered, candidates: candidates)
        #expect(matched.map(\.name) == ["en7"])
        #expect(InterfaceMatching.autoSelected(registered: registered, candidates: candidates) == "en7")
    }

    @Test("一块都不匹配时说清楚现有网卡都有什么 MAC")
    func noMatch() {
        let summary = InterfaceMatching.summary(registered: otherRegistered,
                                                candidates: candidates, locked: nil)
        #expect(summary.contains("没有网卡的 MAC 等于"))
        #expect(summary.contains("en7="))
        #expect(InterfaceMatching.autoSelected(registered: otherRegistered, candidates: candidates) == nil)
    }

    @Test("多块网卡都命中时提示让用户选，并优先有地址的")
    func multipleMatches() {
        var list = candidates
        list.append(InterfaceMACCandidate(name: "en9", ipv4: nil, currentMAC: nil,
                                          hardwareMAC: mac([0xBC, 0xFC, 0xE7, 0xF3, 0x5B, 0x55])))
        let summary = InterfaceMatching.summary(registered: registered, candidates: list, locked: nil)
        #expect(summary.contains("有多块网卡"))
        #expect(InterfaceMatching.autoSelected(registered: registered, candidates: list) == "en7")
    }

    @Test("用户指定网卡后，界面直接说已锁定")
    func locked() {
        let summary = InterfaceMatching.summary(registered: registered, candidates: candidates, locked: "en0")
        #expect(summary.contains("已锁定使用 en0"))
    }
}
