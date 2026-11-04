import Foundation
import Testing
@testable import JLUGateCore

@Suite("国旗 Emoji")
struct CountryFlagTests {
    @Test("ISO 国家码 → 国旗")
    func isoCodes() {
        #expect(CountryFlag.emoji(for: "JP") == "🇯🇵")
        #expect(CountryFlag.emoji(for: "kr") == "🇰🇷")
        #expect(CountryFlag.emoji(for: "CN") == "🇨🇳")
        #expect(CountryFlag.emoji(for: "US") == "🇺🇸")
    }

    @Test("中文国家名也能出旗")
    func chineseNames() {
        #expect(CountryFlag.emoji(for: "日本") == "🇯🇵")
        #expect(CountryFlag.emoji(for: "韩国") == "🇰🇷")
        #expect(CountryFlag.emoji(for: "中国") == "🇨🇳")
    }

    @Test("认不出来就不显示")
    func unknown() {
        #expect(CountryFlag.emoji(for: nil) == nil)
        #expect(CountryFlag.emoji(for: "") == nil)
        #expect(CountryFlag.emoji(for: "XYZ") == nil)
        #expect(CountryFlag.label(nil) == "-")
    }

    @Test("label 组合成 🇯🇵 JP")
    func labels() {
        #expect(CountryFlag.label("JP") == "🇯🇵 JP")
    }
}
