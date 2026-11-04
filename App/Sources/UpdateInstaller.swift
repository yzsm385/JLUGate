import Foundation
import AppKit

/// 一键更新：下载 zip → 解压 → 退出 → 替换 /Applications 里的 App → 重新打开。
///
/// 为什么用脚本：App 不能"自己替换自己"（进程还占着文件）。
/// 所以把替换动作交给一个脱离当前进程的 shell，脚本先等本进程退出，再覆盖、再启动。
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case notInstalledInApplications
        case downloadFailed(String)
        case unzipFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalledInApplications:
                "当前 App 不在 /Applications 里，无法自动替换。请把 App 拖进应用程序文件夹后再用一键更新。"
            case .downloadFailed(let reason): "下载失败：\(reason)"
            case .unzipFailed(let reason): "解压失败：\(reason)"
            }
        }
    }

    static var installedAppURL: URL? {
        let path = Bundle.main.bundleURL
        return path.path.hasPrefix("/Applications/") ? path : nil
    }

    /// 下载并安装。成功后调用 `onReadyToQuit`，由调用方退出 App。
    static func install(from url: URL,
                        progress: @escaping @Sendable (String) -> Void,
                        onReadyToQuit: @escaping @Sendable () -> Void) {
        guard let target = installedAppURL else {
            progress(Failure.notInstalledInApplications.localizedDescription)
            return
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("JLU-Gate-update-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        Task.detached(priority: .userInitiated) {
            progress("下载中…")
            do {
                let (tmp, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw Failure.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let zip = work.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: tmp, to: zip)

                progress("解压中…")
                let extracted = work.appendingPathComponent("extracted", isDirectory: true)
                try run("/usr/bin/ditto", ["-xk", zip.path, extracted.path])
                guard let app = findApp(in: extracted) else {
                    throw Failure.unzipFailed("压缩包里没有 .app")
                }

                // 脚本：等旧进程退出 → 覆盖 → 清 quarantine → 重新打开
                let script = work.appendingPathComponent("install.sh")
                let pid = ProcessInfo.processInfo.processIdentifier
                let body = """
                #!/bin/sh
                set -e
                while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
                rm -rf "\(target.path)"
                ditto "\(app.path)" "\(target.path)"
                xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null || true
                open "\(target.path)"
                """
                try body.write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                      ofItemAtPath: script.path)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [script.path]
                try process.run()

                progress("准备退出并替换…")
                onReadyToQuit()
            } catch {
                progress(error.localizedDescription)
            }
        }
    }

    private static func findApp(in directory: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        if let direct = items.first(where: { $0.pathExtension == "app" }) { return direct }
        for item in items {
            if let nested = findApp(in: item) { return nested }
        }
        return nil
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.unzipFailed("ditto 退出码 \(process.terminationStatus)")
        }
    }
}
