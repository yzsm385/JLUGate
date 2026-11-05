import Testing
import Foundation
@testable import JLUGateCore

@Suite("更新包选择：macOS 14 只装 Compat 包")
struct ReleaseAssetPickerTests {
    private func asset(_ name: String) throws -> ReleaseAssetPicker.Asset {
        ReleaseAssetPicker.Asset(name: name, url: try #require(URL(string: "https://example.com/\(name)")))
    }

    @Test("新版包只挑不带 Compat 的 zip")
    func mainChannel() throws {
        let assets = [try asset("JLU-Gate-v1.0.1-Compat.zip"), try asset("JLU-Gate-v1.0.1.zip")]
        let picked = ReleaseAssetPicker.pick(from: assets, wantsCompat: false)
        #expect(picked?.name == "JLU-Gate-v1.0.1.zip")
    }

    @Test("适配包只挑带 Compat 的，顺序无关")
    func compatChannel() throws {
        let a = [try asset("JLU-Gate-v1.0.1.zip"), try asset("JLU-Gate-v1.0.1-Compat.zip")]
        #expect(ReleaseAssetPicker.pick(from: a, wantsCompat: true)?.name == "JLU-Gate-v1.0.1-Compat.zip")
        let b = a.reversed()
        #expect(ReleaseAssetPicker.pick(from: Array(b), wantsCompat: true)?.name == "JLU-Gate-v1.0.1-Compat.zip")
    }

    @Test("适配包找不到时宁可不给，也不能拿新包兜底")
    func compatNoFallback() throws {
        let assets = [try asset("JLU-Gate-v1.0.1.zip"), try asset("notes.txt")]
        #expect(ReleaseAssetPicker.pick(from: assets, wantsCompat: true) == nil)
    }

    @Test("非 zip 资产不算数")
    func ignoresNonZips() throws {
        let assets = [try asset("JLU-Gate-v1.0.1.dmg"), try asset("JLU-Gate-v1.0.1.zip")]
        #expect(ReleaseAssetPicker.pick(from: assets, wantsCompat: false)?.name == "JLU-Gate-v1.0.1.zip")
        #expect(ReleaseAssetPicker.pick(from: [try asset("JLU-Gate-v1.0.1.dmg")], wantsCompat: false) == nil)
    }
}
