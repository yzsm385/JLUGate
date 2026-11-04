import Foundation
import Testing
@testable import JLUGateCore

@Suite("版本比较（更新提示用）")
struct UpdateVersionTests {
    @Test("新版比旧版大")
    func newer() {
        #expect(UpdateVersion.isNewer("v0.2.2", than: "0.2.1"))
        #expect(UpdateVersion.isNewer("1.0.0", than: "0.9.9"))
        #expect(!UpdateVersion.isNewer("0.2.1", than: "v0.2.1"))
        #expect(!UpdateVersion.isNewer("0.2.0", than: "0.2.1"))
    }
}
