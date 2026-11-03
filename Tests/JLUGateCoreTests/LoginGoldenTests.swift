import Foundation
import Testing
@testable import JLUGateCore

/// **里程碑 1 的验收核心**：342 字节登录包必须与抓包逐字节相同
/// （除 4 处未知区外，见 CHECKLIST §10.1）。
@Suite("登录包黄金复现")
struct LoginGoldenTests {

    private func fixtureLogin() throws -> [UInt8] {
        try Fixtures.hex("login_golden.hex")
    }

    /// 把夹具里的未知区原样喂回去，这样能整包逐字节比对（比"排除法"更强）。
    private func fixtureOverrides(_ bytes: [UInt8]) -> NonceOverrides {
        let L = PacketLayout.Login.self
        return NonceOverrides(
            nonce22: Array(bytes[L.nonce22Offset..<(L.nonce22Offset + L.nonce22Length)]),
            nonce8: Array(bytes[L.nonce8Offset..<(L.nonce8Offset + L.nonce8Length)]),
            nonce10: Array(bytes[L.nonce10Offset..<(L.nonce10Offset + L.nonce10Length)]),
            nonce4: Array(bytes[L.nonce4Offset..<(L.nonce4Offset + L.nonce4Length)]),
            nonce2: Array(bytes[L.nonce2Offset..<(L.nonce2Offset + L.nonce2Length)]))
    }

    private func context(nonces: NonceOverrides) throws -> LoginContext {
        LoginContext(
            account: "20230001",
            password: "test-pass-2024",
            salt: [0x49, 0xCB, 0x72, 0x0F],
            clientIP: IPv4Address("192.0.2.10")!,
            linkLocalIP: IPv4Address("169.254.1.1")!,
            hostname: "test-mac.local",
            mac: MACAddress("02:00:00:00:00:01")!,
            nonceOverrides: nonces)
    }

    @Test("夹具本身就是 342 字节")
    func fixtureLength() throws {
        #expect(try fixtureLogin().count == 342)
    }

    @Test("整包逐字节复现（未知区喂回夹具值）")
    func fullByteEquality() throws {
        let expected = try fixtureLogin()
        let codec = DrcomCodec()
        let produced = try codec.makeLogin(context(nonces: fixtureOverrides(expected)))
        #expect([UInt8](produced) == expected)
    }

    @Test("默认随机填充：除未知区外仍逐字节相同")
    func equalityExceptNonceRegions() throws {
        let expected = try fixtureLogin()
        let codec = DrcomCodec(randomness: SeededRandomSource(seed: 0xC0FFEE))
        let produced = [UInt8](try codec.makeLogin(context(nonces: .empty)))
        #expect(produced.count == expected.count)

        let L = PacketLayout.Login.self
        let nonceRanges = [
            L.nonce22Offset..<(L.nonce22Offset + L.nonce22Length),
            L.nonce8Offset..<(L.nonce8Offset + L.nonce8Length),
            L.nonce10Offset..<(L.nonce10Offset + L.nonce10Length),
            L.nonce4Offset..<(L.nonce4Offset + L.nonce4Length),
            L.nonce2Offset..<(L.nonce2Offset + L.nonce2Length),
        ]
        var mismatches: [String] = []
        for offset in 0..<expected.count {
            if nonceRanges.contains(where: { $0.contains(offset) }) { continue }
            if produced[offset] != expected[offset] {
                mismatches.append(String(format: "0x%03x 期望 %02x 实际 %02x",
                                         offset, expected[offset], produced[offset]))
            }
        }
        #expect(mismatches.isEmpty, "非未知区必须逐字节一致：\(mismatches.joined(separator: ", "))")
    }

    @Test("两次构造的未知区不同（确实随机，不是写死）")
    func nonceIsRandom() throws {
        let codec = DrcomCodec(randomness: SystemRandomSource())
        let first = [UInt8](try codec.makeLogin(context(nonces: .empty)))
        let second = [UInt8](try codec.makeLogin(context(nonces: .empty)))
        let L = PacketLayout.Login.self
        let firstNonce = Array(first[L.nonce22Offset..<(L.nonce22Offset + L.nonce22Length)])
        let secondNonce = Array(second[L.nonce22Offset..<(L.nonce22Offset + L.nonce22Length)])
        #expect(firstNonce != secondNonce)
    }

    @Test("关键字段落在 CHECKLIST 指定的偏移上")
    func fieldOffsets() throws {
        let expected = try fixtureLogin()
        let produced = [UInt8](try DrcomCodec().makeLogin(context(nonces: fixtureOverrides(expected))))
        let L = PacketLayout.Login.self

        #expect(produced[0x000] == 0x03)
        #expect(produced[0x001] == 0x01)
        #expect(Array(produced[0x002..<0x004]) == [0x00, 0x1F])
        #expect(hexString(Array(produced[L.digestAOffset..<(L.digestAOffset + 16)]))
                == "d030ec3cfa269619e0d3c3224b3e9aa6")
        #expect(Array(produced[0x014..<(0x014 + 8)]) == Array("20230001".utf8))
        #expect(Array(produced[0x051..<0x055]) == [192, 0, 2, 10])   // 192.0.2.10
        #expect(Array(produced[0x055..<0x059]) == [169, 254, 1, 1])   // 169.254.1.1
        #expect(String(decoding: produced[0x06E..<(0x06E + 26)].prefix { $0 != 0 }, as: UTF8.self)
                == "test-mac.local")
        #expect(Array(produced[0x0B6..<0x0BB]) == Array("DrCOM".utf8))
        #expect(Array(produced[0x0BB..<0x0C0]) == [0x00, 0xCF, 0x07, 0x31, 0x00])
        #expect(String(decoding: produced[0x0C0..<0x0C6], as: UTF8.self) == "25.6.0")
        #expect(String(decoding: produced[0x0F6..<(0x0F6 + 40)], as: UTF8.self)
                == "56c68373463f4cd5b73dd3ac5e3673000a5fdd7e")
        #expect(Array(produced[0x136..<0x13A]) == [0x31, 0x00, 0x00, 0x0A])
        #expect(Array(produced[0x144..<0x146]) == [0x02, 0x0C])
        #expect(Array(produced[0x14C..<0x152]) == [0x02, 0x00, 0x00, 0x00, 0x00, 0x01])
    }

    @Test("没有链路本地地址时全 0，长度不变")
    func noLinkLocal() throws {
        var ctx = try context(nonces: .empty)
        ctx.linkLocalIP = nil
        let produced = [UInt8](try DrcomCodec(randomness: SeededRandomSource(seed: 1)).makeLogin(ctx))
        #expect(produced.count == 342)
        #expect(Array(produced[0x055..<0x059]) == [0, 0, 0, 0])
    }

    @Test("账号超 32 字节必须报错，不能截断")
    func accountTooLong() throws {
        var ctx = try context(nonces: .empty)
        ctx.account = String(repeating: "9", count: 33)
        #expect(throws: DrcomError.self) {
            _ = try DrcomCodec().makeLogin(ctx)
        }
    }

    @Test("第二次抓包的登录帧同样可复现（证明不是只对着一个样本调参）")
    func secondLoginFrame() throws {
        // 20:29:52 那次成功登录：digest f112b888…，salt 6ecb720f，密码未知（摘要直接喂回）
        let session = try Fixtures.session()
        let logins = session.all("c2s", length: 342)
        #expect(logins.count == 2)
        guard logins.count == 2 else { return }
        let expected = logins[1]

        // 密码未知，所以只校验"结构区"：把夹具摘要与未知区喂进去，
        // 通过 NonceOverrides + 一个把 digest 顶掉的路径不可行，
        // 因此这里改成：用 makeLogin 的产物替换摘要区后整包比对。
        var produced = [UInt8](try DrcomCodec(randomness: FixedRandomSource(pool:
            Array(expected[0x03A..<0x050] + expected[0x061..<0x069]
                  + expected[0x13A..<0x144] + expected[0x146..<0x14A]
                  + expected[0x154..<0x156])))
            .makeLogin(context(nonces: .empty)))
        produced[0x004..<0x014] = expected[0x004..<0x014]

        let L = PacketLayout.Login.self
        let nonceRanges = [
            L.nonce22Offset..<(L.nonce22Offset + L.nonce22Length),
            L.nonce8Offset..<(L.nonce8Offset + L.nonce8Length),
            L.nonce10Offset..<(L.nonce10Offset + L.nonce10Length),
            L.nonce4Offset..<(L.nonce4Offset + L.nonce4Length),
            L.nonce2Offset..<(L.nonce2Offset + L.nonce2Length),
            0x004..<0x014,
        ]
        var mismatches: [String] = []
        for offset in 0..<expected.count where !nonceRanges.contains(where: { $0.contains(offset) }) {
            if produced[offset] != expected[offset] {
                mismatches.append(String(format: "0x%03x", offset))
            }
        }
        #expect(mismatches.isEmpty, "偏移不一致：\(mismatches.prefix(10).joined(separator: ","))")
    }
}
