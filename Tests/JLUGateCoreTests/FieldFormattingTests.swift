import Foundation
import Testing
@testable import JLUGateCore

@Suite("输入框自动补分隔符")
struct FieldFormattingTests {
    @Test("IPv4：满 3 位自动补点，已有分隔符保持原样")
    func ipv4AutoDots() {
        #expect(FieldFormatting.ipv4Input("192") == "192.")
        #expect(FieldFormatting.ipv4Input("192.168.1.10") == "192.168.1.10")
        #expect(FieldFormatting.ipv4Input("10.0.0.1") == "10.0.0.1")
    }

    @Test("IPv4：每段最多 3 位、最多 4 段")
    func ipv4Limits() {
        #expect(FieldFormatting.ipv4Input("192.0.2.10.5") == "192.0.2.10")
        #expect(FieldFormatting.ipv4Input("1234") == "123.", "超长段会被截到 3 位")
    }

    @Test("四格输入：拆与合")
    func splitJoinIPv4() {
        #expect(FieldFormatting.splitIPv4("192.168.1.10") == ["192", "168", "1", "10"])
        #expect(FieldFormatting.splitIPv4("10.0") == ["10", "0", "", ""])
        #expect(FieldFormatting.joinIPv4(["192", "168", "1", "10"]) == "192.168.1.10")
        #expect(FieldFormatting.joinIPv4(["10", "0", "0", "1"]) == "10.0.0.1")
        #expect(FieldFormatting.joinIPv4(["", "", "", ""]) == "")
    }

    @Test("MAC 六格：拆与合")
    func splitJoinMAC() {
        #expect(FieldFormatting.splitMAC("02:00:00:00:00:01")
                == ["02", "00", "00", "00", "00", "01"])
        #expect(FieldFormatting.splitMAC("0200") == ["02", "00", "", "", "", ""])
        #expect(FieldFormatting.joinMAC(["02", "00", "00", "00", "00", "01"])
                == "02:00:00:00:00:01")
        #expect(FieldFormatting.joinMAC(["", "", "", "", "", ""]) == "")
    }

    @Test("IPv4：每段位数不足时不会乱补点")
    func ipv4ShortGroups() {
        #expect(FieldFormatting.ipv4Input("10") == "10")
        #expect(FieldFormatting.ipv4Input("10.") == "10.")
        #expect(FieldFormatting.ipv4Input("") == "")
    }

    @Test("MAC：每 2 位自动补冒号，最多 6 段")
    func macAutoColons() {
        #expect(FieldFormatting.macInput("02") == "02:")
        #expect(FieldFormatting.macInput("0200") == "02:00:")
        #expect(FieldFormatting.macInput("020000000001") == "02:00:00:00:00:01")
        #expect(FieldFormatting.macInput("02:00:00:00:00:01") == "02:00:00:00:00:01", "粘贴带冒号也能归一化")
        #expect(FieldFormatting.macInput("020000000001234") == "02:00:00:00:00:01", "超长截断")
    }

    @Test("DNS：逗号分隔的多个地址分别补点")
    func dnsList() {
        #expect(FieldFormatting.ipv4ListInput("10.10.10.10,172.16.0.53") == "10.10.10.10, 172.16.0.53", "只补点，不猜分段")
        #expect(FieldFormatting.ipv4ListInput("10.10.10.10,") == "10.10.10.10, ")
    }
}

