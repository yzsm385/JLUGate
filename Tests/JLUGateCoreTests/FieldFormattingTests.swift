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


@Suite("单行输入实时补分隔符（光标稳定版）")
struct LiveFieldFormattingTests {
    @Test("IPv4：满 3 位补点，最多 4 段")
    func ipv4() {
        #expect(FieldFormatting.liveIPv4("192") == "192.")
        #expect(FieldFormatting.liveIPv4("192168") == "192.168.")
        #expect(FieldFormatting.liveIPv4("19216810110") == "192.168.101.10")
        #expect(FieldFormatting.liveIPv4("1.2.3.4") == "123.4", "分隔符由输入决定，粘进来的会被规整")
    }

    @Test("MAC：每 2 位补冒号")
    func mac() {
        #expect(FieldFormatting.liveMAC("02") == "02:")
        #expect(FieldFormatting.liveMAC("0200") == "02:00:")
        #expect(FieldFormatting.liveMAC("020000000001") == "02:00:00:00:00:01")
    }

    @Test("超长输入被截断，不会越界")
    func limits() {
        #expect(FieldFormatting.liveIPv4("19216810110155") == "192.168.101.101", "第 5 段会被丢掉")
        #expect(FieldFormatting.liveMAC("0200000000012345") == "02:00:00:00:00:01")
    }
}

@Suite("整体地址拆分（预填/粘贴）")
struct SplitAddressTests {
    @Test("中间点、ASCII 点、冒号都能拆")
    func separators() {
        #expect(FieldFormatting.splitAddress("203·0·113·11", groups: 4, groupSize: 3)
                == ["203", "0", "113", "11"])
        #expect(FieldFormatting.splitAddress("203.0.113.11", groups: 4, groupSize: 3)
                == ["203", "0", "113", "11"])
        #expect(FieldFormatting.splitAddress("02:00:00:00:00:01", groups: 6, groupSize: 2)
                == ["02", "00", "00", "00", "00", "01"])
    }

    @Test("没有分隔符：按组长度切，不会全塞进第一个框")
    func chunking() {
        #expect(FieldFormatting.splitAddress("203011311", groups: 4, groupSize: 3)
                == ["203", "011", "311", ""])
        #expect(FieldFormatting.splitAddress("020000000001", groups: 6, groupSize: 2)
                == ["02", "00", "00", "00", "00", "01"])
    }

    @Test("段数不足会补空，段数过多被截断")
    func padding() {
        #expect(FieldFormatting.splitAddress("10", groups: 4, groupSize: 3) == ["10", "", "", ""])
        #expect(FieldFormatting.splitAddress("1·2·3·4·5", groups: 4, groupSize: 3)
                == ["1", "2", "3", "4"])
    }
}

@Suite("地址解析：中间点也要认")
struct AddressParsingCompatTests {
    @Test("IPv4：· / . / 全角 都能解析")
    func ipv4() {
        #expect(IPv4Address("203·0·113·11")?.description == "203.0.113.11")
        #expect(IPv4Address("203.0.113.11")?.description == "203.0.113.11")
        #expect(IPv4Address(" 203．0．113．11 ")?.description == "203.0.113.11")
    }

    @Test("MAC：· / : / - 都能解析")
    func mac() {
        #expect(MACAddress("02·00·00·00·00·01")?.description == "02:00:00:00:00:01")
        #expect(MACAddress("02:00:00:00:00:01")?.description == "02:00:00:00:00:01")
        #expect(MACAddress("02-00-00-00-00-01")?.description == "02:00:00:00:00:01")
    }
}
