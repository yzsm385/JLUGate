import Foundation
import Security

/// 凭据存储：**正式签名版**用 Keychain，**ad-hoc/未签名版**用 0600 文件。
///
/// 为什么必须分两种：
/// - Keychain 条目的 ACL 绑定代码签名。ad-hoc 每次构建签名都不同，于是每次启动读旧条目
///   macOS 都要弹"允许访问钥匙串"——对开发版来说是纯粹的打扰。
/// - 正式签名（Developer ID）身份稳定，Keychain 才是有意义且安全的存法。
///
/// 两条路径的 API 完全一样，调用方不用关心。
enum CredentialStore {
    enum Backend: String {
        case keychain
        case file
    }

    static let service = "dev.jlugate.app"

    enum StoreError: Error {
        case unexpectedStatus(OSStatus)
        case fileWriteFailed(String)
    }

    // MARK: 后端选择

    /// 有 TeamIdentifier = 正式签名 → Keychain；否则（ad-hoc / 未签名）→ 文件。
    static let backend: Backend = hasTeamIdentifier() ? .keychain : .file

    static var backendDescription: String {
        switch backend {
        case .keychain: "Keychain（正式签名）"
        case .file: "本地文件 0600（开发版，无 Keychain 授权弹窗）"
        }
    }

    private static func hasTeamIdentifier() -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return false }
        return dictionary[kSecCodeInfoTeamIdentifier as String] != nil
    }

    // MARK: 对外 API

    static func save(password: String, account: String) throws {
        guard !account.isEmpty else { return }
        switch backend {
        case .keychain: try saveToKeychain(password: password, account: account)
        case .file: try saveToFile(password: password, account: account)
        }
    }

    static func password(for account: String) -> String? {
        guard !account.isEmpty else { return nil }
        switch backend {
        case .keychain: return passwordFromKeychain(account: account)
        case .file: return passwordFromFile(account: account)
        }
    }

    // MARK: 密码"是否被服务器验证过"

    /// 只有**成功登录过**的密码才算已验证。未验证的密码不允许在启动时静默复用——
    /// 否则一次输错会被永久记住，用户点多少次重试都是同一个错密码。
    private static func verifiedKey(_ account: String) -> String { "credentialVerified.\(account)" }

    static func markVerified(account: String) {
        guard !account.isEmpty else { return }
        UserDefaults.standard.set(Date(), forKey: verifiedKey(account))
    }

    static func markUnverified(account: String) {
        guard !account.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: verifiedKey(account))
    }

    static func verifiedAt(account: String) -> Date? {
        UserDefaults.standard.object(forKey: verifiedKey(account)) as? Date
    }

    static func delete(account: String) {
        guard !account.isEmpty else { return }
        markUnverified(account: account)
        switch backend {
        case .keychain: deleteFromKeychain(account: account)
        case .file: deleteFromFile(account: account)
        }
    }

    // MARK: Keychain

    private static func saveToKeychain(password: String, account: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
    }

    private static func passwordFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: 文件（仅开发版）

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JLUGate", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private static func loadFile() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dictionary
    }

    private static func saveToFile(password: String, account: String) throws {
        var dictionary = loadFile()
        dictionary[account] = password
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(dictionary)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: fileURL.path)
        } catch {
            throw StoreError.fileWriteFailed(error.localizedDescription)
        }
    }

    private static func passwordFromFile(account: String) -> String? {
        loadFile()[account]
    }

    private static func deleteFromFile(account: String) {
        var dictionary = loadFile()
        dictionary[account] = nil
        if let data = try? JSONEncoder().encode(dictionary) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
