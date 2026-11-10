import Foundation
import Testing
@testable import JLUGateCore

@Suite("更新包校验清单")
struct ChecksumManifestTests {
    private let a = String(repeating: "a1", count: 32)
    private let b = String(repeating: "b2", count: 32)

    @Test("标准 shasum 输出：按文件名挑出对应的哈希")
    func picksMatchingFile() {
        let text = """
        \(a)  JLU-Gate-v1.4.11.zip
        \(b)  JLU-Gate-v1.4.11-Compat.zip
        """
        #expect(ChecksumManifest.checksum(for: "JLU-Gate-v1.4.11.zip", in: text) == a)
        #expect(ChecksumManifest.checksum(for: "JLU-Gate-v1.4.11-Compat.zip", in: text) == b)
        #expect(ChecksumManifest.checksum(for: "JLU-Gate-v9.9.9.zip", in: text) == nil)
    }

    @Test("二进制模式（* 前缀）、多空格、CRLF 都要认")
    func toleratesFormatting() {
        let text = "\(a) *JLU-Gate-v1.4.11.zip\r\n\(b)\tJLU-Gate-v1.4.11.dmg\r\n"
        #expect(ChecksumManifest.checksum(for: "JLU-Gate-v1.4.11.zip", in: text) == a)
        #expect(ChecksumManifest.checksum(for: "JLU-Gate-v1.4.11.dmg", in: text) == b)
    }

    @Test("文件名里有空格也能匹配")
    func spacesInName() {
        let text = "\(a)  JLU Gate v1.4.11.zip"
        #expect(ChecksumManifest.checksum(for: "JLU Gate v1.4.11.zip", in: text) == a)
    }

    @Test("不是 64 位十六进制的行、注释、空行一律跳过")
    func ignoresJunk() {
        let text = """
        # 这是注释
        not-a-hash  JLU-Gate-v1.4.11.zip
        \(a)  JLU-Gate-v1.4.11.zip
        """
        #expect(ChecksumManifest.checksum(for: "JLU-Gate-v1.4.11.zip", in: text) == a)
    }

    @Test("返回的哈希统一小写（大小写不同不算失败）")
    func lowercased() {
        let upper = String(repeating: "AB", count: 32)
        #expect(ChecksumManifest.checksum(for: "x.zip", in: "\(upper)  x.zip") == upper.lowercased())
    }

    @Test("空清单 / 空文本不会崩，也不会乱匹配")
    func emptyInput() {
        #expect(ChecksumManifest.checksum(for: "x.zip", in: "") == nil)
        #expect(ChecksumManifest.checksum(for: "", in: "") == nil)
    }
}
