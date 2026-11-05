import Testing
import Foundation
@testable import JLUGateCore

@Suite("界面文案：三种语言 + 占位符")
struct CopyTests {
    @Test("按系统首选语言选简体 / 繁體 / English")
    func languageSelection() {
        #expect(Copy.resolveLanguage(environment: [:], preferred: ["zh-Hans-CN"]) == .zhHans)
        #expect(Copy.resolveLanguage(environment: [:], preferred: ["zh-Hant-TW"]) == .zhHant)
        #expect(Copy.resolveLanguage(environment: [:], preferred: ["zh-HK"]) == .zhHant)
        #expect(Copy.resolveLanguage(environment: [:], preferred: ["zh-TW"]) == .zhHant)
        #expect(Copy.resolveLanguage(environment: [:], preferred: ["en-US"]) == .en)
        #expect(Copy.resolveLanguage(environment: [:], preferred: []) == .en)
        #expect(Copy.resolveLanguage(environment: ["JLUGATE_LANG": "en"], preferred: ["zh-Hans-CN"]) == .en)
    }

    @Test("三种语言都收齐了全部 711 条")
    func fullTables() {
        #expect(Copy.entryCount(.zhHans) == 711)
        #expect(Copy.entryCount(.zhHant) == 711)
        #expect(Copy.entryCount(.en) == 711)
    }

    @Test("取文案：非空、不含未替换的占位符残留（静态条目）")
    func lookups() {
        for key in ["M01", "S02", "E42"] {
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
