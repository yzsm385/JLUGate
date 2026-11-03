import Foundation
import Testing
@testable import JLUGateCore

@Suite("MD5（RFC 1321）")
struct MD5Tests {
    @Test("RFC 1321 标准向量", arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("a", "0cc175b9c0f1b6a831c399e269772661"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
        ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
        ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
         "d174ab98d277d9f5a5611c2c9f419d9f"),
        ("12345678901234567890123456789012345678901234567890123456789012345678901234567890",
         "57edf4a22be3c955ac49da2e2107b67a"),
    ])
    func vectors(input: String, expected: String) {
        #expect(hexString(MD5.hash([UInt8](input.utf8))) == expected)
    }

    @Test("跨 64 字节块边界（55/56/63/64/65/1000 字节）", arguments: [
        (55, "6912ee65fff2d9f9ce2508cddf8bcda0"),
        (56, "51fdd1acda72405dfdfa03fcb85896d7"),
        (63, "48a6295221902e8e0938f773a7185e72"),
        (64, "b2d3f56bc197fd985d5965079b5e7148"),
        (65, "8bd7053801c768420faf816fadba971c"),
        (1000, "a24f1e3ef66950e1327f210e3997ba2c"),
    ])
    func blockBoundaries(length: Int, expected: String) {
        // 55 → 不补块；56 → 补一整块；其余覆盖块对齐与跨块。
        // 期望值由 python hashlib 生成（命令见 docs/progress.md）。
        let bytes = (0..<length).map { UInt8($0 % 251) }
        #expect(hexString(MD5.hash(bytes)) == expected)
    }

    @Test("同一输入两次结果稳定")
    func deterministic() {
        let bytes = (0..<1000).map { UInt8($0 % 251) }
        #expect(MD5.hash(bytes) == MD5.hash(bytes))
    }

    @Test("百万个 a 的摘要")
    func millionA() {
        let data = [UInt8](repeating: Character("a").asciiValue!, count: 1_000_000)
        #expect(hexString(MD5.hash(data)) == "7707d6ae4e027c70eea2a935c2296f21")
    }
}

@Suite("摘要 A（黄金向量）")
struct DigestATests {
    @Test("CLAUDE/CHECKLIST 的实测向量")
    func goldenVector() {
        let digest = DrcomCodec.digestA(password: "test-pass-2024", salt: [0x49, 0xCB, 0x72, 0x0F])
        #expect(hexString(digest) == "d030ec3cfa269619e0d3c3224b3e9aa6")
    }

    @Test("salt 取错一个就完全算不对（这就是真机上最难查的坑）")
    func saltSensitivity() {
        let right = DrcomCodec.digestA(password: "test-pass-2024", salt: [0x49, 0xCB, 0x72, 0x0F])
        let neighbor = DrcomCodec.digestA(password: "test-pass-2024", salt: [0x6E, 0xCB, 0x72, 0x0F])
        #expect(right != neighbor)
        #expect(hexString(neighbor) != "d030ec3cfa269619e0d3c3224b3e9aa6")
    }
}
