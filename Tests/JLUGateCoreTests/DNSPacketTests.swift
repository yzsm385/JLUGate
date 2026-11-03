import Foundation
import Testing
@testable import JLUGateCore

@Suite("DNS（自带解析，不用系统 DNS）")
struct DNSPacketTests {

    @Test("查询报文结构：ID / RD / 单问题 / 标签与根")
    func queryLayout() {
        let query = DNSPacket.makeQuery(name: "connectivitycheck.gstatic.com", id: 0xABCD)
        #expect(query[0] == 0xAB)
        #expect(query[1] == 0xCD)
        #expect(Array(query[2...3]) == [0x01, 0x00], "RD=1")
        #expect(Array(query[4...5]) == [0x00, 0x01], "QDCOUNT=1")
        #expect(Array(query[6...11]) == [0, 0, 0, 0, 0, 0])

        // 首标签长度 = 17 ("connectivitycheck")
        #expect(query[12] == 17)
        #expect(Array(query[13..<(13 + 17)]) == Array("connectivitycheck".utf8))
        #expect(query.count == 12 + (1 + 17) + (1 + 7) + (1 + 3) + 1 + 4)
        #expect(query[30] == 7, "第二个标签长度（gstatic）")
        #expect(Array(query[31..<38]) == Array("gstatic".utf8))
        #expect(query[38] == 3)
        #expect(Array(query[39..<42]) == Array("com".utf8))
        #expect(Array(query.suffix(4)) == [0x00, 0x01, 0x00, 0x01], "QTYPE=A, QCLASS=IN")
    }

    /// 一段手写的应答：一个 CNAME + 两个 A 记录，带压缩指针（真实应答就是这个形状）。
    private func response(withCompression: Bool) -> [UInt8] {
        var bytes: [UInt8] = []
        // header: id=0x0001, flags=0x8180, qd=1, an=2
        bytes += [0x00, 0x01, 0x81, 0x80, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00]
        // question: "a.test" A IN
        bytes += [1, UInt8(ascii: "a"), 4] + Array("test".utf8) + [0]
        bytes += [0x00, 0x01, 0x00, 0x01]

        // answer 1: CNAME（名字用指针 0x0C 指回问题）
        bytes += [0xC0, 0x0C, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x06]
        bytes += [3] + Array("cdn".utf8) + [0xC0, 0x10]

        // answer 2: A 记录（名字用指针指到 answer1 的目标名）
        let targetPointer: [UInt8] = withCompression ? [0xC0, 0x21] : [3] + Array("cdn".utf8) + [0xC0, 0x10]
        bytes += targetPointer
        bytes += [0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x04]
        bytes += [192, 0, 2, 10]
        return bytes
    }

    @Test("压缩指针与非压缩名字都能解析出 A 记录")
    func parseBothForms() throws {
        let compressed = try DNSPacket.parseARecords(response(withCompression: true))
        #expect(compressed.map(\.description) == ["192.0.2.10"])

        let expanded = try DNSPacket.parseARecords(response(withCompression: false))
        #expect(expanded.map(\.description) == ["192.0.2.10"])
    }

    @Test("NODATA / 无 A 记录返回空数组，而不是崩")
    func noAnswers() throws {
        var bytes: [UInt8] = [0x00, 0x01, 0x81, 0x80, 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0]
        bytes += [1, UInt8(ascii: "a"), 4] + Array("test".utf8) + [0, 0x00, 0x1C, 0x00, 0x01]
        #expect(try DNSPacket.parseARecords(bytes).isEmpty)
    }

    @Test("截断报文必须抛错，不能读越界")
    func truncated() {
        let full = response(withCompression: true)
        for cut in [0, 5, 12, 20, full.count - 2] {
            #expect(throws: DrcomError.self) {
                _ = try DNSPacket.parseARecords(Array(full.prefix(cut)))
            }
        }
    }

    @Test("rcode 非 0（比如 NXDOMAIN=3）要报错")
    func nxdomain() {
        var bytes = response(withCompression: true)
        bytes[3] = 0x83   // rcode = 3
        #expect(throws: DrcomError.self) {
            _ = try DNSPacket.parseARecords(bytes)
        }
    }
}
