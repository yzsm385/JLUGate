import Foundation
import Testing
@testable import JLUGateCore

/// 用社区维护实现（jlu-drcom-ng v2.0.0）生成的黄金向量逐字节比对。
/// 这些向量是"能被 JLU 服务端接受"的布局：基础长度 338，密码段从 312 起。
@Suite("登录包黄金复现（当前 JLU 客户端版本）")
struct LoginV2GoldenTests {
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
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/login_jlu_v2_golden.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Case].self, from: data)
    }

    @Test("三个密码长度的登录包都要逐字节一致")
    func golden() throws {
        let cases = try loadCases()
        #expect(cases.count >= 3)
        for item in cases {
            var saltBytes: [UInt8] = []
            var index = item.seed.startIndex
            while index < item.seed.endIndex {
                let next = item.seed.index(index, offsetBy: 2)
                saltBytes.append(UInt8(item.seed[index..<next], radix: 16)!)
                index = next
            }
            let context = LoginContext(
                account: item.account,
                password: item.password,
                salt: saltBytes,
                clientIP: IPv4Address("192.0.2.10")!,
                linkLocalIP: nil,
                hostname: "ignored",
                mac: MACAddress(item.mac)!)
            let produced = try DrcomCodec().makeLogin(context)
            #expect(produced.count == item.length, "\(item.account) 长度应为 \(item.length)")
            let expected = Data(hexString: item.packet)
            if produced != expected {
                let diff = zip(produced, expected).enumerated()
                    .first { $0.element.0 != $0.element.1 }?.offset ?? -1
                Issue.record("\(item.account) 首次差异在 0x\(String(diff, radix: 16))")
            }
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
