import Foundation

/// 从 GitHub Release 的资产里挑安装包。
///
/// 同一个 Release 里有两份 zip：新版（macOS 26，Liquid Glass）和旧版适配（macOS 14）。
/// 两者同名同 bundle id，装错了直接打不开——所以规则必须写死：
/// **适配包只认名字里带 Compat 的那份，绝不能用新包兜底**。
public enum ReleaseAssetPicker {
    public struct Asset: Equatable, Sendable {
        public let name: String
        public let url: URL

        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    public static func isCompat(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".zip") && lower.contains("compat")
    }

    public static func isZip(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".zip")
    }

    /// - Parameter wantsCompat: 当前跑的是不是 macOS 14 适配包
    public static func pick(from assets: [Asset], wantsCompat: Bool) -> Asset? {
        let zips = assets.filter { isZip($0.name) }
        if wantsCompat {
            return zips.first(where: { isCompat($0.name) })
        }
        return zips.first(where: { !isCompat($0.name) }) ?? zips.first
    }
}
