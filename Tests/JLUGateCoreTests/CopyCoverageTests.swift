import Testing
import Foundation
@testable import JLUGateCore

/// 文案表漏条目的回归守卫。
///
/// 背景：`Copy.t("GPA01")` 这种调用如果文案表里没有这个 key，`Copy.t` 会把
/// **编号本身**返回给界面，用户看到的就是「GPA01 / GPA02」。这种问题编译期
/// 发现不了，所以在这里扫一遍源码里所有静态 key。
@Suite("界面文案：源码用到的静态 key 三种语言都要有")
struct CopyCoverageTests {
    @Test("没有漏翻的 Copy.t / Copy.f key")
    func everyStaticKeyExists() throws {
        let root = try repoRoot()
        let directories = [
            "Sources/JLUGateCore",
            "Sources/JLUGateNet",
            "Sources/jlugate-probe",
            "App/Sources",
            "App-Compat/Sources",
        ]
        let pattern = #"Copy\.(?:t|f)\("([A-Za-z][A-Za-z0-9]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        var keys = Set<String>()

        for directory in directories {
            let base = root.appendingPathComponent(directory)
            guard FileManager.default.fileExists(atPath: base.path),
                  let enumerator = FileManager.default.enumerator(
                    at: base, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let ns = text as NSString
                for match in regex.matches(in: text,
                                           range: NSRange(location: 0, length: ns.length)) {
                    guard let range = Range(match.range(at: 1), in: text) else { continue }
                    keys.insert(String(text[range]))
                }
            }
        }

        #expect(!keys.isEmpty, "没扫到任何 Copy.t / Copy.f 调用，检查源目录")

        let missing = keys.filter { key in
            CopyLanguage.allCases.contains { !Copy.hasEntry(key, in: $0) }
        }
        #expect(missing.isEmpty,
                "以下 key 在源码里用了，但文案表缺条目：\(missing.sorted().joined(separator: ", "))")
    }

    /// 从测试文件位置向上找 Package.swift，避免依赖 `swift test` 的 cwd。
    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
