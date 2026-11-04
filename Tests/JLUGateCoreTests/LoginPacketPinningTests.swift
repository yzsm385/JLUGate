import Foundation
import Testing
@testable import JLUGateCore

/// 登录报文的"钉子"：只要协议关键路径被误改，这两条就会立刻红。
/// 目的：不再出现"某个无关改动把连接弄坏"。
@Suite("登录报文稳定性（防止无关改动破坏连接）")
struct LoginPacketPinningTests {
    private func context(variantPassword password: String = "test-pass-2024") -> LoginContext {
        LoginContext(
            account: "20230001",
            password: password,
            salt: [0x49, 0xcb, 0x72, 0x0f],
            clientIP: IPv4Address("192.0.2.10")!,
            linkLocalIP: IPv4Address("169.254.1.1"),
            hostname: "test-mac.local",
            mac: MACAddress("02:00:00:00:00:01")!,
            nonceOverrides: NonceOverrides(nonce2: [0xAA, 0xBB]))
    }

    @Test("当前版本：长度固定为 375，摘要 A 固定")
    func currentVariantPinned() throws {
        let frame = try DrcomCodec().makeLogin(context())
        #expect(frame.count == 375)
        let digest = DrcomCodec.digestA(password: "test-pass-2024",
                                        salt: [0x49, 0xcb, 0x72, 0x0f])
        #expect([UInt8](frame[4..<20]) == digest, "摘要 A 必须由 03 01 salt password 生成")
        // 关键常量：0x38=0x20、0x6E 起 LIYUANYUAN、0xB6 起 DrCOM
        #expect([UInt8](frame[0x38..<0x3A]) == [0x20, 0x03])
        #expect(String(decoding: frame[0x6E..<0x78], as: UTF8.self) == "LIYUANYUAN")
        #expect(String(decoding: frame[0xB6..<0xBB], as: UTF8.self) == "DrCOM")
    }

    @Test("旧版：长度 346，尾部随机字节照传入值写")
    func legacyVariantPinned() throws {
        let frame = try DrcomCodec().makeLogin(context(), variant: .legacy)
        #expect(frame.count == 346)
        #expect([UInt8](frame[(frame.count - 2)..<frame.count]) == [0xAA, 0xBB])
        #expect([UInt8](frame[4..<20]) == DrcomCodec.digestA(
            password: "test-pass-2024", salt: [0x49, 0xcb, 0x72, 0x0f]))
    }
}
