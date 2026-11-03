import Foundation
import Testing
@testable import JLUGateCore

/// 鲁棒性：任意字节都不许让编解码层崩（只能抛错或返回 unknown）。
///
/// 真机上线后最先遇到的就是"收到一个不在帧表里的包"，
/// 这条测试保证那一刻是打日志而不是闪退。
@Suite("编解码健壮性（随机字节）")
struct FuzzTests {
    private func makeRandomPayloads(count: Int, seed: UInt64) -> [[UInt8]] {
        let random = SeededRandomSource(seed: seed)
        var payloads: [[UInt8]] = []
        for index in 0..<count {
            // 长度覆盖：空、比所有帧短、正好落在帧表长度上、比最长帧还长
            let lengths = [0, 1, 2, 19, 20, 21, 37, 38, 39, 40, 45, 72, 76, 80, 341, 342, 343, 500]
            let length = lengths[index % lengths.count]
            var bytes = random.bytes(count: length)
            // 一半的样本把首字节改成已知类型，让解析真的走进去
            if index % 2 == 0, !bytes.isEmpty {
                let types: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0xFF]
                bytes[0] = types[index % types.count]
            }
            payloads.append(bytes)
        }
        return payloads
    }

    @Test("classify 对 3000 个随机载荷永不崩溃")
    func classifyNeverTraps() {
        let codec = DrcomCodec(randomness: SeededRandomSource(seed: 1))
        let payloads = makeRandomPayloads(count: 3000, seed: 0xF00D)
        var unknownCount = 0
        for payload in payloads {
            let frame = codec.classify(Data(payload))
            if case .unknown = frame { unknownCount += 1 }
        }
        #expect(unknownCount > 0, "随机字节里应该有一堆认不出的包")
    }

    @Test("解析器只抛错，不越界")
    func parsersOnlyThrow() {
        let codec = DrcomCodec()
        for payload in makeRandomPayloads(count: 1200, seed: 0xBEEF) {
            let data = Data(payload)
            _ = try? codec.parseChallengeReply(data)
            _ = try? codec.parseLoginReply(data)
            _ = try? codec.parseLoginFailureReason(data)
            _ = try? codec.parseKeepAliveAReply(data)
            _ = try? codec.parseKeepAliveBReply(data)
        }
    }

    @Test("登录包越界读写会被拦住")
    func writerBounds() {
        var writer = ByteWriter(count: 4)
        #expect(throws: DrcomError.self) { try writer.put(UInt32(1), at: 2) }
        #expect(throws: DrcomError.self) { try writer.put(UInt8(1), at: 4) }

        let reader = ByteReader([0x01, 0x02])
        #expect(throws: DrcomError.self) { try reader.u16(at: 1, endian: .big) }
        #expect(throws: DrcomError.self) { try reader.slice(-1, 1) }
    }

    @Test("DNS 解析同样不会被畸形报文打崩")
    func dnsFuzz() {
        let random = SeededRandomSource(seed: 42)
        for length in stride(from: 0, through: 200, by: 7) {
            var bytes = random.bytes(count: length)
            if length > 4 { bytes[2] = 0x81; bytes[3] = 0x80 }
            _ = try? DNSPacket.parseARecords(bytes)
        }
    }
}
