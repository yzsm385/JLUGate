import Foundation
import JLUGateCore

/// 区分「正式安装」与「便携副本」。
///
/// 为什么需要：同一份 App 放在 `/Applications` 和 SD 卡/下载目录时，bundle id 相同、
/// 配置目录也相同——两份同时运行就会互相覆盖配置、抢 61440、抢登录项。
/// 现在按位置分身份：
/// - `/Applications/...` → 正式身份：用原来的配置目录，允许注册开机自启，会接管旧实例；
/// - 其他位置 → 便携身份：独立配置目录（`JLUGate-Portable`），不注册自启，
///   也不去动正式身份那份——两份可以同时存在、互不干扰。
enum AppIdentity {
    static var isInstalled: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    static var displaySuffix: String {
        guard !isInstalled else { return "" }
        switch Copy.language {
        case .zhHans: return "（便携）"
        case .zhHant: return "（便攜）"
        case .en: return " (portable)"
        }
    }

    /// Application Support 下的目录名
    static var supportDirectoryName: String {
        isInstalled ? "JLUGate" : "JLUGate-Portable"
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    /// 便携副本第一次运行时，把正式身份已有的配置复制过来，避免"像丢了一样"。
    static func migrateIfNeeded() {
        guard !isInstalled else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let legacy = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JLUGate", isDirectory: true)
        for name in ["config.json", "config.backup.json", "credentials.json"] {
            let target = supportDirectory.appendingPathComponent(name)
            let source = legacy.appendingPathComponent(name)
            guard !manager.fileExists(atPath: target.path),
                  manager.fileExists(atPath: source.path) else { continue }
            try? manager.copyItem(at: source, to: target)
            FileLogger.shared.log("便携副本：已从正式配置复制 \(name)")
        }
    }

    /// 某个运行中的副本是否与当前身份同类（正式 vs 便携）
    static func sameKind(as bundleURL: URL) -> Bool {
        bundleURL.path.hasPrefix("/Applications/") == isInstalled
    }
}
