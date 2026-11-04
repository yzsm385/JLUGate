import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import JLUGateCore

/// 单实例：菜单栏工具被复制成两份会互相抢 61440，动作很隐蔽（一人顶两人的号）。
enum SingleInstance {
    /// 处理"同一 App 有两个副本在跑"的情况。
    ///
    /// 规则（按优先级）：
    /// 1. 没有别的实例 → 正常启动；
    /// 2. 别的实例**构建号相同** → 激活它，自己退出（避免两个引擎抢 61440）；
    /// 3. 别的实例**构建号更旧** → 自动退出旧实例，由新版本接管（不弹对话框，
    ///    否则用户会以为"双击新包没反应"，一直在用旧版本）；
    /// 4. 别的实例构建号更新（比如从旧包启动，但新包已在跑）→ 让位给更新的。
    @MainActor
    static func claim(terminateSelf: @escaping @MainActor () -> Void) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else {
            warnAboutStaleCopies(currentBuild: currentBuild)
            return true
        }

        let existingBuild = buildNumber(of: existing.bundleURL) ?? "unknown"
        FileLogger.shared.log("已有实例：pid=\(existing.processIdentifier) build=\(existingBuild)；"
                              + "本进程 build=\(currentBuild)")

        if existingBuild == currentBuild || existingBuild > currentBuild {
            // 同一个构建（或对方更新）：把自己让位给对方
            existing.activate()
            FileLogger.shared.log("让位给已运行的实例（build \(existingBuild)）")
            terminateSelf()
            return false
        }

        // 对方更旧：自动接管，不打扰用户
        existing.terminate()
        for _ in 0..<20 where !existing.isTerminated {
            usleep(100_000)
        }
        if !existing.isTerminated {
            kill(existing.processIdentifier, SIGTERM)
            usleep(300_000)
        }
        FileLogger.shared.log("自动退出旧实例 build \(existingBuild)，由 build \(currentBuild) 接管")
        Notifier.postVersionTakeover(oldBuild: existingBuild, newBuild: currentBuild)
        return true
    }

    /// 启动时顺手检查 /Applications 里是否还留着更旧的副本——那是"版本冲突"的常见来源。
    @MainActor
    private static func warnAboutStaleCopies(currentBuild: String) {
        let candidates = [
            URL(fileURLWithPath: "/Applications/JLU Gate.app"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications/JLU Gate.app"),
        ]
        guard let running = Bundle.main.bundleURL.standardizedFileURL as URL? else { return }
        for url in candidates where url.standardizedFileURL != running {
            guard FileManager.default.fileExists(atPath: url.path),
                  let build = buildNumber(of: url),
                  build != currentBuild else { continue }
            let newer = build > currentBuild
            FileLogger.shared.log("磁盘上还有另一份 JLU Gate：\(url.path) build=\(build)"
                                  + (newer ? "（比当前新）" : "（比当前旧，建议删掉）"))
        }
    }

    /// 读某个 App 包里的构建号，用来判断新旧。
    private static func buildNumber(of url: URL?) -> String? {
        guard let url,
              let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        else { return nil }
        return plist["CFBundleVersion"] as? String
    }
}

/// 文件日志：`~/Library/Logs/JLUGate/agent.log`，到 2 MB 就滚动（PLAN §9）。
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "dev.jlugate.filelogger")
    private let maxBytes = 2 * 1024 * 1024
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// 标准位置建议 `~/Library/Logs/JLUGate`；不可写时（沙箱 / 测试 HOME）退到 `NSTemporaryDirectory()`。
    private lazy var directory: URL = {
        let standard = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JLUGate", isDirectory: true)
        if Self.prepare(standard) { return standard }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("JLUGate", isDirectory: true)
        _ = Self.prepare(fallback)
        return fallback
    }()

    private static func prepare(_ directory: URL) -> Bool {
        do {
            FilePrivacy.secureDirectory(directory)
            let probe = directory.appendingPathComponent(".write-test")
            try Data("ok".utf8).write(to: probe)
            try? FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private var fileURL: URL { directory.appendingPathComponent("agent.log") }
    private var rotatedURL: URL { directory.appendingPathComponent("agent.1.log") }

    func log(_ message: String) {
        queue.async { [self] in
            let line = "\(formatter.string(from: Date())) \(message)\n"
            do {
                FilePrivacy.secureDirectory(directory)
                rotateIfNeeded()
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                } else {
                    try FilePrivacy.write(Data(line.utf8), to: fileURL)
                }
                FilePrivacy.secureFile(fileURL)
            } catch {
                NSLog("JLUGate: 写日志失败 \(error.localizedDescription)")
            }
        }
    }

    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size >= maxBytes else { return }
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }

    /// 诊断包要"最近 500 行"。
    func tail(_ lines: Int = 500) -> String {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        return all.suffix(lines).joined(separator: "\n")
    }
}

/// 网络参数卡片：导出成文本 / 二维码，换机或重装时粘贴恢复（PLAN §9）。
///
/// **不含密码**——卡片只承载"学校分配的网络参数"，凭据永远留在 Keychain。
enum ConfigCard {
    static func text(config: AppConfig, profile: AppConfig.NetworkProfile) -> String {
        NetworkCard.format(account: config.account,
                           profile: (ip: profile.ip, mask: profile.mask, gateway: profile.gateway,
                                     dns: profile.dns, mac: profile.registeredMAC),
                           link: config.link,
                           server: config.server,
                           serverPort: config.serverPort)
    }

    /// 二维码（CoreImage 生成，不依赖第三方库）。
    static func qrImage(for text: String, scale: CGFloat = 8) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width,
                                                      height: scaled.extent.height))
    }
}


/// 版本与构建号：用于确认"现在跑的是哪一版"（排障时最常被问的问题）。
enum BuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    static var display: String { "v\(version) (\(build))" }
}
