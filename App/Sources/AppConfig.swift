import Foundation

/// 配置 schema（对齐 PLAN 附录 C，`schemaVersion = 3`）。
///
/// 放在 `~/Library/Application Support/JLUGate/config.json`，**不含密码**
/// （密码在 Keychain，见 `CredentialStore`）。
struct AppConfig: Codable, Sendable {
    struct NetworkProfile: Codable, Sendable {
        var ip: String?
        var mask: String?
        var gateway: String?
        var dns: [String] = []
        /// 学校平台登记的 MAC（不是"当前接口 MAC"）。
        var registeredMAC: String?
        var interfaceHint: String?
        var configuredAt: String?
    }

    struct RouteGuard: Codable, Sendable {
        var mode = "auto"
        var helperAuthorized: Bool?
        var remindOnLaunch = true
    }

    struct Portal: Codable, Sendable {
        var entryURL: String?
        /// 最近一次被门户拦下时记下的入口地址（App 内"校园网门户"用它）
        var lastKnownURL: String?
        var silentRetryOnce = true
        var promptCooldownSeconds = 300
    }

    struct KeepAlive: Codable, Sendable {
        var interval = 10.0
        var jitter = 0.1
        var missTolerance = 3
    }

    struct Probe: Codable, Sendable {
        var interval = 30.0
        var timeout = 3.0
        var failTolerance = 2
    }

    struct BackoffSettings: Codable, Sendable {
        var base = 2.0
        var cap = 60.0
        var jitter = 3.0
        var maxAttempts = 8
    }

    var schemaVersion = 3
    var account = ""
    var link = "auto"
    var server = "10.100.61.3"
    var serverPort = 61440
    var localPort = 61440
    var channel = "nw"
    var interfaceLock: String?
    var accounts: [String: NetworkProfile] = [:]
    var autoDetect = true
    var routeGuard = RouteGuard()
    var portal = Portal()
    var keepAlive = KeepAlive()
    var probe = Probe()
    var backoff = BackoffSettings()
    var launchAtLogin = true
    /// 启动时自动连接（默认开；有"成功连过"的记录才生效）。
    var autoConnect = true
    /// 用户在小火箭里自述的模式：config / proxy / direct / scene / unknown
    var declaredProxyMode = "unknown"
    /// 系统使用私有/随机 MAC 时，认证报文改用登记的 MAC。
    var useRegisteredMACForAuth = false
    /// 上次成功认证成功的时间；非空 = 这台机器上"记住且连过"。
    var lastSuccessfulLogin: String?
    var logLevel = "info"

    var currentProfile: NetworkProfile? {
        get { accounts[account] }
        set { accounts[account] = newValue }
    }
}

/// 极简 JSON 落盘（不引入第三方）。写盘失败只记日志，不打断用户操作。
struct ConfigStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JLUGate", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func save(_ config: AppConfig) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("JLUGate: 配置写入失败 \(error)")
        }
    }
}
