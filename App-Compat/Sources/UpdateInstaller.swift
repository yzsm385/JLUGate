import Foundation
import JLUGateCore
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
                Copy.t("N15")
            case .downloadFailed(let reason): Copy.f("N16", reason)
            case .unzipFailed(let reason): Copy.f("N17", reason)
            }
        }
    }

    static var installedAppURL: URL? {
        let path = Bundle.main.bundleURL
        return path.path.hasPrefix("/Applications/") ? path : nil
    }

    /// 下载并安装。成功后调用 `onReadyToQuit`，由调用方退出 App。
    /// 失败时调 `onFailure`（不要把错误塞进 progress，调用方要分清"进行中"和"失败了"）。
    static func install(from url: URL,
                        progress: @escaping @Sendable (String) -> Void,
                        onFailure: @escaping @Sendable (String) -> Void,
                        onReadyToQuit: @escaping @Sendable () -> Void) {
        guard let target = installedAppURL else {
            onFailure(Failure.notInstalledInApplications.localizedDescription)
            return
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("JLU-Gate-update-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        // 安装脚本放在工作目录**外面**：装完要把 work 整个删掉（安装包 + 解压出来的副本），
        // 别把正在执行的脚本一起删了。
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("JLU-Gate-install-\(UUID().uuidString).sh")

        Task.detached(priority: .userInitiated) {
            progress(Copy.t("N18"))
            do {
                let zip = work.appendingPathComponent("update.zip")
                try await download(url: url, to: zip, progress: progress)

                progress(Copy.t("N19"))
                let extracted = work.appendingPathComponent("extracted", isDirectory: true)
                try run("/usr/bin/ditto", ["-xk", zip.path, extracted.path])
                // zip 已经解开，先把安装包删掉，别白占几百 MB
                try? FileManager.default.removeItem(at: zip)
                guard let app = findApp(in: extracted) else {
                    throw Failure.unzipFailed(Copy.t("N20"))
                }

                // 脚本：等旧进程退出 → 覆盖 → 清 quarantine → 重新打开 → 清理临时文件
                let pid = ProcessInfo.processInfo.processIdentifier
                let body = """
                #!/bin/sh
                set -e
                while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
                rm -rf "\(target.path)"
                ditto "\(app.path)" "\(target.path)"
                xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null || true
                open "\(target.path)"
                # 装完把下载的 zip、解压出来的副本、这个脚本都清掉
                rm -rf "\(work.path)"
                rm -f "$0"
                """
                try body.write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                      ofItemAtPath: script.path)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [script.path]
                try process.run()

                progress(Copy.t("N21"))
                onReadyToQuit()
            } catch {
                try? FileManager.default.removeItem(at: work)
                onFailure(error.localizedDescription)
            }
        }
    }

    /// 带进度的下载：面板上能看见百分比，卡住 20 秒就明确报错（而不是一直转圈）。
    private static func download(url: URL,
                                 to destination: URL,
                                 progress: @escaping @Sendable (String) -> Void) async throws {
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Result<(URL, Int), Error>?
            func set(_ result: Result<(URL, Int), Error>) { lock.lock(); value = result; lock.unlock() }
            var result: Result<(URL, Int), Error>? { lock.lock(); defer { lock.unlock() }; return value }
        }
        let box = Box()
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let task = URLSession.shared.downloadTask(with: request) { temporary, response, error in
            if let error { box.set(.failure(error)); return }
            guard let temporary, let http = response as? HTTPURLResponse else {
                box.set(.failure(Failure.downloadFailed("没有收到文件")))
                return
            }
            box.set(.success((temporary, http.statusCode)))
        }
        task.resume()

        var lastPercent = -1
        var lastBytes: Int64 = -1
        var lastChange = ContinuousClock.now
        while box.result == nil {
            try await Task.sleep(for: .milliseconds(300))
            // 只要字节数在涨就算有进展（不能只看 5% 的台阶：慢速链路上一个台阶可能要很久）
            let written = task.progress.completedUnitCount
            if written > lastBytes {
                lastBytes = written
                lastChange = ContinuousClock.now
            }
            let percent = Int(task.progress.fractionCompleted * 100)
            if percent >= 0, percent != lastPercent, percent % 5 == 0 {
                lastPercent = percent
                progress("\(Copy.t("N18")) \(percent)%")
            }
            // 20 秒一个字节都没多就认输，别让人对着"正在下载"干等
            if ContinuousClock.now - lastChange > .seconds(20) {
                task.cancel()
                throw Failure.downloadFailed("下载卡住了（20 秒没有任何数据），检查代理/网络后重试")
            }
        }
        guard let result = box.result else { throw Failure.downloadFailed("下载失败") }
        let (temporary, status) = try result.get()
        guard status == 200 else { throw Failure.downloadFailed("HTTP \(status)") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
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
