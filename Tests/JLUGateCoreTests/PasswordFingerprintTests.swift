import Foundation
import Testing
@testable import JLUGateCore

@Suite("密码指纹")
struct PasswordFingerprintTests {
    @Test("同一串密码指纹稳定，不同串不同")
    func stability() {
        #expect(PasswordFingerprint.of("test-pass-2024") == PasswordFingerprint.of("test-pass-2024"))
        #expect(PasswordFingerprint.of("test-pass-2024") != PasswordFingerprint.of("test-pass-2025"))
        #expect(PasswordFingerprint.of("test-pass-2024") != PasswordFingerprint.of("test-pass-2024 "))
        #expect(PasswordFingerprint.of("test-pass-2024").count == 8)
    }

    @Test("描述里含长度与指纹，且不出现密码本身")
    func description() {
        let text = PasswordFingerprint.describe("secret-123")
        #expect(text.contains("10 字符"))
        #expect(!text.contains("secret-123"))
    }
}
