import Foundation
import CryptoKit
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
    ///
    /// `expectedSHA256`：官方清单里这一项的摘要。给了就先校验再解压——
    /// 宁可在这里失败，也别把半个包装进 /Applications 再打不开。
    static func install(from url: URL,
                        expectedSHA256: String? = nil,
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

                // 校验：有官方清单就按清单核，别把截断/被替换的包装进去
                if let expectedSHA256 {
                    progress(Copy.t("N27"))
                    let actual = try SHA256File.digest(of: zip)
                    guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                        FileLogger.shared.log("更新包校验失败：期望 \(expectedSHA256) 实际 \(actual)")
                        throw Failure.downloadFailed(Copy.t("N28"))
                    }
                    FileLogger.shared.log("更新包校验通过：\(actual)")
                }

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

    /// 带进度的下载。
    ///
    /// 三处针对「更新慢」的改动：
    /// 1. 进度按 1% 报，并且带上下载速度——以前只在 5% 的整数台阶上报，
    ///    几 MB 的包在慢速链路上要等很久才跳一次字，看起来像卡死了。
    /// 2. 卡住判定按**实际吞吐**而不是「20 秒一个字节都没有」：真正的卡死是
    ///    「还在滴字节但慢到没意义」，以前那种情况会一直转到天荒地老。
    /// 3. 支持断点续传（Range）：中途失败重试时不必从 0 开始。
    private static func download(url: URL,
                                 to destination: URL,
                                 progress: @escaping @Sendable (String) -> Void) async throws {
        // 续传：上一次失败留下的半截文件继续用
        let resumeFrom = fileSize(destination)
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                try await downloadOnce(url: url, to: destination,
                                       resumeFrom: attempt == 0 ? resumeFrom : fileSize(destination),
                                       progress: progress)
                return
            } catch {
                lastError = error
                if Task.isCancelled { throw error }
                if attempt == 0 {
                    FileLogger.shared.log("更新下载失败，带续传重试一次：\(error.localizedDescription)")
                    progress("\(Copy.t("N18"))（重试中…）")
                }
            }
        }
        throw lastError ?? Failure.downloadFailed("下载失败")
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// 下载任务与下载线程之间共享的状态（只在这里用）。
    private final class Transfer: @unchecked Sendable {
        private let lock = NSLock()
        private var _finished: Result<Void, Error>?
        private var _expected: Int64 = -1
        private var _written: Int64

        init(written: Int64) { _written = written }

        var finished: Result<Void, Error>? {
            lock.lock(); defer { lock.unlock() }; return _finished
        }
        func finish(_ value: Result<Void, Error>) {
            lock.lock(); _finished = value; lock.unlock()
        }
        var expected: Int64 {
            get { lock.lock(); defer { lock.unlock() }; return _expected }
            set { lock.lock(); _expected = newValue; lock.unlock() }
        }
        var written: Int64 {
            get { lock.lock(); defer { lock.unlock() }; return _written }
            set { lock.lock(); _written = newValue; lock.unlock() }
        }
    }

    private static func downloadOnce(url: URL,
                                     to destination: URL,
                                     resumeFrom: Int64,
                                     progress: @escaping @Sendable (String) -> Void) async throws {
        let transfer = Transfer(written: resumeFrom)
        var request = URLRequest(url: url)
        // 60 秒是连接/空闲超时，不是总时长；总时长由下面的吞吐判定兜
        request.timeoutInterval = 60
        request.setValue("JLU-Gate/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        if resumeFrom > 0 {
            request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
        }

        let delegate = DownloadDelegate(destination: destination,
                                        resumeFrom: resumeFrom,
                                        transfer: transfer)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        // 更新包必须拿最新的那份，不许命中缓存
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let task = session.downloadTask(with: request)
        task.resume()

        // 停滞判定：按「最近若干秒的平均速度」算，慢到 <8 KB/s 就当卡死。
        // 以前是「20 秒零字节」，于是一个 0.5 KB/s 的连接能耗上一小时。
        var lastBytes = resumeFrom
        var lastSampleAt = ContinuousClock.now
        var lastReportedPercent = -1
        while transfer.finished == nil {
            try await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled {
                task.cancel()
                throw CancellationError()
            }
            let written = transfer.written
            let expected = transfer.expected
            let now = ContinuousClock.now
            let elapsed = Double((now - lastSampleAt).components.seconds)
                + Double((now - lastSampleAt).components.attoseconds) / 1e18
            guard elapsed >= 1 else { continue }

            let speed = Double(written - lastBytes) / max(elapsed, 0.001)
            lastBytes = written
            lastSampleAt = now

            // 进度：1% 一报并带速度；总量未知时只报已下载量
            if expected > 0 {
                let percent = Int(min(100, max(0, Double(written) * 100 / Double(expected))))
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    progress("\(Copy.t("N18")) \(percent)%（\(speedText(speed))）")
                }
            } else {
                progress("\(Copy.t("N18")) \(bytesText(written))（\(speedText(speed))）")
            }

            // 平均速度低于 8 KB/s 且还没下完：判卡死，明确报错而不是无限等
            if speed < 8_000, expected <= 0 || written < expected {
                task.cancel()
                throw Failure.downloadFailed("下载几乎停滞（约 \(speedText(speed))），检查代理/网络后重试")
            }
        }
        guard let result = transfer.finished else { throw Failure.downloadFailed("下载失败") }
        try result.get()
    }

    private static func bytesText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func speedText(_ bytesPerSecond: Double) -> String {
        let text = ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)),
                                             countStyle: .file)
        return "\(text)/s"
    }

    /// 用 delegate 拿「实时字节数 + 边下边写」，而不是轮询 `Progress`。
    ///
    /// 好处：
    /// - 进度是**真实写入磁盘的字节**，不是 URLSession 估算的 fractionCompleted；
    /// - 立刻能判断 HTTP 状态（206 续传 / 200 从头 / 416 已经下完），
    ///   以前要等整个任务结束才知道状态码；
    /// - 支持断点续传：Range 请求得到的 206 直接追加到半截文件后面。
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let resumeFrom: Int64
        private let transfer: Transfer

        init(destination: URL, resumeFrom: Int64, transfer: Transfer) {
            self.destination = destination
            self.resumeFrom = resumeFrom
            self.transfer = transfer
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            transfer.written = resumeFrom + totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                transfer.expected = resumeFrom + totalBytesExpectedToWrite
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            do {
                guard let http = downloadTask.response as? HTTPURLResponse else {
                    throw Failure.downloadFailed("没有收到文件")
                }
                switch http.statusCode {
                case 200, 206:
                    break
                case 416:
                    // 服务器说 Range 越界：半截文件其实已经完整了
                    transfer.finish(.success(()))
                    return
                default:
                    throw Failure.downloadFailed("HTTP \(http.statusCode)")
                }
                // 200 = 服务器忽略了 Range：必须整体覆盖，不能追加（否则文件错位）
                let appending = (http.statusCode == 206 && resumeFrom > 0)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if appending {
                    let handle = try FileHandle(forWritingTo: destination)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: try Data(contentsOf: location, options: .mappedIfSafe))
                } else {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: location, to: destination)
                }
                transfer.written = Self.size(of: destination)
                transfer.finish(.success(()))
            } catch {
                transfer.finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard let error else { return }   // 成功路径已在 didFinishDownloadingTo 收尾
            transfer.finish(.failure(Failure.downloadFailed(
                (error as NSError).localizedDescription)))
        }

        private static func size(of url: URL) -> Int64 {
            ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
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

/// 流式 SHA-256（不把整个 zip 读进内存）。
///
/// 用 CryptoKit：App 只跑在 macOS 上，不需要 Core 那种跨平台洁癖。
enum SHA256File {
    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
