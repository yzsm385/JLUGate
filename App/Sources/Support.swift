import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// 单实例：菜单栏工具被复制成两份会互相抢 61440，动作很隐蔽（一人顶两人的号）。
enum SingleInstance {
    /// 已有实例就激活它并返回 false（调用方应退出）。
    @MainActor
    static func claim(terminateSelf: @escaping @MainActor () -> Void) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return true }
        existing.activate(options: [.activateIgnoringOtherApps])
        terminateSelf()
        return false
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

    private var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JLUGate", isDirectory: true)
    }

    private var fileURL: URL { directory.appendingPathComponent("agent.log") }
    private var rotatedURL: URL { directory.appendingPathComponent("agent.1.log") }

    func log(_ message: String) {
        queue.async { [self] in
            let line = "\(formatter.string(from: Date())) \(message)\n"
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                rotateIfNeeded()
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                } else {
                    try Data(line.utf8).write(to: fileURL)
                }
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
        """
        # JLU Gate 网络参数卡
        账号: \(config.account)
        链路: \(config.link)
        IP: \(profile.ip ?? "")
        掩码: \(profile.mask ?? "")
        网关: \(profile.gateway ?? "")
        DNS: \(profile.dns.joined(separator: ","))
        登记MAC: \(profile.registeredMAC ?? "")
        服务器: \(config.server):\(config.serverPort)
        """
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
