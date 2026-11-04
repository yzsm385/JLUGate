import Foundation

/// 本机文件的权限收紧：配置与日志只允许当前用户读写。
///
/// macOS 默认 `~/Library/Application Support` 下的文件是 0644（同机其他用户可读），
/// 而 config.json 里有账号、学号。这里统一 mkdir 0700 / chmod 0600。
public enum FilePrivacy {
    public static let directoryMode: Int = 0o700
    public static let fileMode: Int = 0o600

    @discardableResult
    public static func secureDirectory(_ url: URL) -> Bool {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        do {
            try manager.setAttributes([.posixPermissions: directoryMode], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func secureFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.setAttributes([.posixPermissions: fileMode],
                                                  ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    /// 按 0600 写入（先写临时文件再替换，避免中途留下 0644 的窗口期）。
    public static func write(_ data: Data, to url: URL) throws {
        secureDirectory(url.deletingLastPathComponent())
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: [.atomic])
        _ = try? FileManager.default.setAttributes([.posixPermissions: fileMode],
                                                  ofItemAtPath: temp.path)
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temp, to: url)
        _ = secureFile(url)
    }

    /// 权限是否已收紧（测试与自检用）。
    public static func mode(of url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}
