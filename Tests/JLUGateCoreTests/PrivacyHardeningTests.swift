import Foundation
import Testing
@testable import JLUGateCore

@Suite("隐私：脱敏与文件权限")
struct PrivacyHardeningTests {
    @Test("账号/学号/MAC/主机名都不会完整出现")
    func redaction() {
        #expect(Redact.account("student2024") == "stu***")
        #expect(!Redact.account("student2024").contains("ent2024"))
        #expect(Redact.studentID("2023012345") == "2023******")
        #expect(Redact.mac("02:00:00:00:00:01") == "02:00:00:**:**:*")
        #expect(!Redact.mac("02:00:00:00:00:01").contains("00:00:01"))
        #expect(Redact.hostname("test-mac.local") == "tes***")
        #expect(Redact.account("") == "-")
    }

    @Test("打印报文时能把账号抹掉")
    func scrubPacket() {
        let hex = "0301001f" + "73747564656e7432303234" + "00"
        let scrubbed = Redact.scrubAccount(in: hex, account: "student2024")
        #expect(!scrubbed.contains("73747564656e7432303234"))
        #expect(scrubbed.hasPrefix("0301001f"))
    }

    @Test("配置/日志目录应被收紧为 0700，文件 0600")
    func permissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jlugate-privacy-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("JLUGate")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        #expect(FilePrivacy.secureDirectory(dir))
        #expect(FilePrivacy.mode(of: dir) == 0o700)
        let file = dir.appendingPathComponent("config.json")
        try FilePrivacy.write(Data("{}".utf8), to: file)
        #expect(FilePrivacy.mode(of: file) == 0o600)
        try? FileManager.default.removeItem(at: root)
    }
}
