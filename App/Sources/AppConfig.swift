import Foundation
import JLUGateCore

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
    /// 学号（只用于"认出你的学院"，可留空）
    var studentID = ""
    /// 学号前缀 → 学院官网 host（本机学习，不上传）
    var collegePrefixMap: [String: String] = [:]
    /// 手动选定的学院官网 host（学号认不出时的兜底）
    var myCollegeHost = ""
    /// GPA 网页里手动选定的学院代码（空 = 按学号/账号自动识别）
    var gpaCollegeCode = ""
    var link = "auto"
    var server = "10.100.61.3"
    var serverPort = 61440
    var localPort = 61440
    var channel = "bsd"
    var interfaceLock: String?
    var accounts: [String: NetworkProfile] = [:]
    var autoDetect = true
    /// 只有排障时才打印完整登录报文（默认关：报文里有账号与 MAC）
    var verboseAuthLogging = false
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
    /// 兼容模式：绕开液态玻璃渲染（虚拟机/老显卡上更稳），重启生效。
    var compatibilityMode = false
    /// 可选：IP2Location / MaxMind 的密钥（留空则跳过该来源）
    var ip2locationKey = ""
    var maxmindAccount = ""
    var maxmindLicense = ""
    /// 上次成功认证成功的时间；非空 = 这台机器上"记住且连过"。
    var lastSuccessfulLogin: String?
    var logLevel = "info"

    var currentProfile: NetworkProfile? {
        get { accounts[account] }
        set { accounts[account] = newValue }
    }

    // MARK: 向前兼容解码（关键）

    /// 老版本 `config.json` 缺少新增字段时**不能整份丢弃**——那会把账号、服务器、
    /// 静态 IP/网关/MAC 全部重置成默认值（0.2.0 起就踩过这个坑：更新后"突然连不上"）。
    /// 每个字段都用 `decodeIfPresent`，缺失就落回默认值。
    enum CodingKeys: String, CodingKey {
        case schemaVersion, account, studentID, collegePrefixMap, myCollegeHost, gpaCollegeCode
        case link, server, serverPort, localPort, channel, interfaceLock, accounts
        case autoDetect, verboseAuthLogging, routeGuard, portal, keepAlive, probe
        case backoff, launchAtLogin, autoConnect, declaredProxyMode
        case useRegisteredMACForAuth, compatibilityMode
        case ip2locationKey, maxmindAccount, maxmindLicense
        case lastSuccessfulLogin, logLevel
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 3
        account = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        studentID = try c.decodeIfPresent(String.self, forKey: .studentID) ?? ""
        collegePrefixMap = try c.decodeIfPresent([String: String].self, forKey: .collegePrefixMap) ?? [:]
        myCollegeHost = try c.decodeIfPresent(String.self, forKey: .myCollegeHost) ?? ""
        gpaCollegeCode = try c.decodeIfPresent(String.self, forKey: .gpaCollegeCode) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? "auto"
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? "10.100.61.3"
        serverPort = try c.decodeIfPresent(Int.self, forKey: .serverPort) ?? 61440
        localPort = try c.decodeIfPresent(Int.self, forKey: .localPort) ?? 61440
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "bsd"
        interfaceLock = try c.decodeIfPresent(String.self, forKey: .interfaceLock)
        accounts = try c.decodeIfPresent([String: NetworkProfile].self, forKey: .accounts) ?? [:]
        autoDetect = try c.decodeIfPresent(Bool.self, forKey: .autoDetect) ?? true
        verboseAuthLogging = try c.decodeIfPresent(Bool.self, forKey: .verboseAuthLogging) ?? false
        routeGuard = try c.decodeIfPresent(RouteGuard.self, forKey: .routeGuard) ?? RouteGuard()
        portal = try c.decodeIfPresent(Portal.self, forKey: .portal) ?? Portal()
        keepAlive = try c.decodeIfPresent(KeepAlive.self, forKey: .keepAlive) ?? KeepAlive()
        probe = try c.decodeIfPresent(Probe.self, forKey: .probe) ?? Probe()
        backoff = try c.decodeIfPresent(BackoffSettings.self, forKey: .backoff) ?? BackoffSettings()
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
        declaredProxyMode = try c.decodeIfPresent(String.self, forKey: .declaredProxyMode) ?? "unknown"
        useRegisteredMACForAuth = try c.decodeIfPresent(Bool.self, forKey: .useRegisteredMACForAuth) ?? false
        compatibilityMode = try c.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false
        ip2locationKey = try c.decodeIfPresent(String.self, forKey: .ip2locationKey) ?? ""
        maxmindAccount = try c.decodeIfPresent(String.self, forKey: .maxmindAccount) ?? ""
        maxmindLicense = try c.decodeIfPresent(String.self, forKey: .maxmindLicense) ?? ""
        lastSuccessfulLogin = try c.decodeIfPresent(String.self, forKey: .lastSuccessfulLogin)
        logLevel = try c.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
    }
}

/// 极简 JSON 落盘（不引入第三方）。写盘失败只记日志，不打断用户操作。
struct ConfigStore {
    static var directory: URL { AppIdentity.supportDirectory }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL) else {
            // 文件不在：先看有没有上一份备份（重装/写坏时用得上）
            return loadBackup() ?? AppConfig()
        }
        if let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }
        // 解不开：**绝不静默覆盖**——留一份原文件，再尝试备份
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let broken = directory.appendingPathComponent("config.unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: fileURL, to: broken)
        FileLogger.shared.log("配置解析失败，已保留原文件：\(broken.lastPathComponent)")
        return loadBackup() ?? AppConfig()
    }

    private static func backupURL() -> URL {
        directory.appendingPathComponent("config.backup.json")
    }

    private static func loadBackup() -> AppConfig? {
        guard let data = try? Data(contentsOf: backupURL()) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func save(_ config: AppConfig) {
        do {
            FilePrivacy.secureDirectory(directory)
            // 覆盖前留一份上一版（只保留一份，够用且不堆垃圾）
            if let old = try? Data(contentsOf: fileURL) {
                try? FilePrivacy.write(old, to: backupURL())
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // 配置里有账号/学号：按 0600 写，且不留 0644 的窗口期
            try FilePrivacy.write(encoder.encode(config), to: fileURL)
        } catch {
            NSLog("JLUGate: 配置写入失败 \(error)")
        }
    }
}
