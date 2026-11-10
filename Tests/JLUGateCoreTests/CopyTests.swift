import Testing
import Foundation
@testable import JLUGateCore

@Suite("界面文案：三种语言 + 占位符")
struct CopyTests {
    @Test("按系统首选语言选简体 / 繁體 / English")
    func languageSelection() {
        #expect(Copy.resolveLanguage(preferred: ["zh-Hans-CN"]) == .zhHans)
        #expect(Copy.resolveLanguage(preferred: ["zh-Hant-TW"]) == .zhHant)
        #expect(Copy.resolveLanguage(preferred: ["zh-HK"]) == .zhHant)
        #expect(Copy.resolveLanguage(preferred: ["zh-TW"]) == .zhHant)
        #expect(Copy.resolveLanguage(preferred: ["en-US"]) == .en)
        #expect(Copy.resolveLanguage(preferred: []) == .en)
        // 环境变量 / 设置里的选择在 Copy.language 里统一处理，这里只测系统语言映射
        #expect(Copy.resolveLanguage(preferred: ["zh-Hans-CN", "en-US"]) == .zhHans)
    }

    @Test("三种语言都收齐了全部 786 条")
    func fullTables() {
        #expect(Copy.entryCount(.zhHans) == 786)
        #expect(Copy.entryCount(.zhHant) == 786)
        #expect(Copy.entryCount(.en) == 786)
    }

    @Test("设置里选的界面语言能覆盖环境变量和系统语言")
    func effectiveLanguage() {
        // 纯函数，不改全局状态（否则并行跑的其他测试会被带偏）
        #expect(Copy.effectiveLanguage(stored: .zhHant, forced: "zh-Hans", preferred: ["en-US"]) == .zhHant)
        #expect(Copy.effectiveLanguage(stored: .en, forced: nil, preferred: ["zh-Hans-CN"]) == .en)
        #expect(Copy.effectiveLanguage(stored: nil, forced: "zh-Hant", preferred: ["en-US"]) == .zhHant)
        #expect(Copy.effectiveLanguage(stored: nil, forced: nil, preferred: ["zh-Hant-TW"]) == .zhHant)
        #expect(Copy.effectiveLanguage(stored: nil, forced: nil, preferred: ["en-GB"]) == .en)
    }

    @Test("取文案：非空、不含未替换的占位符残留（静态条目）")
    func lookups() {
        for key in ["M01", "S02", "E42", "GPA01", "GPA12"] {
            #expect(!Copy.t(key).isEmpty)
            #expect(Copy.t(key) != key)
        }
        #expect(Copy.t("NOPE") == "NOPE")
    }

    @Test("占位符按顺序替换，参数多了忽略、少了保留")
    func placeholders() {
        #expect(Copy.substitute("A {…} B {…}", ["1", "2"]) == "A 1 B 2")
        #expect(Copy.substitute("A {…}", []) == "A {…}")
        #expect(Copy.substitute("A {…}", ["1", "2"]) == "A 1")
        #expect(Copy.substitute("no placeholder", ["1"]) == "no placeholder")
    }
}
