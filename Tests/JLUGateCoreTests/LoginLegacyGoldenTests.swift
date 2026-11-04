import Foundation
import Testing
@testable import JLUGateCore

/// 旧版布局（2026-11-02 抓包实测）黄金向量：用来在服务端要求旧版本时兜底。
@Suite("登录包黄金复现（旧版布局）")
struct LoginLegacyGoldenTests {
    struct Case: Decodable {
        let account: String
        let password: String
        let mac: String
        let seed: String
        let length: Int
        let packet: String
    }

    private func loadCases() throws -> [Case] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/login_jlu_legacy_golden.json")
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    @Test("旧版布局逐字节一致")
    func golden() throws {
        for item in try loadCases() {
            var salt: [UInt8] = []
            var index = item.seed.startIndex
            while index < item.seed.endIndex {
                let next = item.seed.index(index, offsetBy: 2)
                salt.append(UInt8(item.seed[index..<next], radix: 16)!)
                index = next
            }
            let context = LoginContext(
                account: item.account, password: item.password, salt: salt,
                clientIP: IPv4Address("192.0.2.10")!, linkLocalIP: IPv4Address("169.254.1.1"),
                hostname: "test-mac.local", mac: MACAddress(item.mac)!,
                nonceOverrides: NonceOverrides(nonce2: [0xAA, 0xBB]))
            let produced = try DrcomCodec().makeLogin(context, variant: .legacy)
            #expect(produced.count == item.length)
            #expect(produced == Data(hexString: item.packet), "\(item.account) 旧版布局不一致")
        }
    }
}

private extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
