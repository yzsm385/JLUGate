import Foundation

/// 启动看门狗：如果上一次启动在初始化早期就死掉（闪退），下次进"安全模式"。
///
/// 安全模式只做三件事：**不自动连接、不恢复已保存的密码、不重复刷新诊断**，
/// 让用户能进设置把坏掉的配置改回来（或直接重置），而不是一直闪退。
enum LaunchGuard {
    private static var directory: URL { ConfigStore.directory }

    private static var markerURL: URL { directory.appendingPathComponent(".launch-marker") }
    private static var crashCountURL: URL { directory.appendingPathComponent(".crash-count") }

    /// 上一次启动是否没走完（据此判断"闪退过"）。
    static var crashedLastTime: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    static var consecutiveCrashes: Int {
        guard let text = try? String(contentsOf: crashCountURL, encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// 启动时调用：写下标记，返回是否要进安全模式。
    static func beginLaunch() -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let crashed = crashedLastTime
        let count = crashed ? consecutiveCrashes + 1 : 0
        try? String(count).write(to: crashCountURL, atomically: true, encoding: .utf8)
        try? "\(Date().timeIntervalSince1970)".write(to: markerURL, atomically: true, encoding: .utf8)
        FileLogger.shared.log("启动看门狗：上次\(crashed ? "异常退出" : "正常")，连续 \(count) 次")
        if crashed { harvestCrashReport() }
        return crashed && count >= 1
    }

    /// 上次闪退过：把系统崩溃报告复制到我们的日志目录，并把关键几行写进 agent.log。
    /// 这样用户只要给一个文件/一段日志，就能定位闪退原因。
    static func harvestCrashReport() {
        let reportsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: reportsDir.path) else { return }
        let newest = names
            .filter { $0.hasPrefix("JLUGate-") && $0.hasSuffix(".ips") }
            .sorted()
            .last
        guard let newest else {
            FileLogger.shared.log("看门狗：没找到 JLUGate 的崩溃报告")
            return
        }
        let source = reportsDir.appendingPathComponent(newest)
        let target = directory.appendingPathComponent("crash-\(newest)")
        try? FileManager.default.copyItem(at: source, to: target)

        let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
        let interesting = text.split(separator: "\n")
            .filter { line in
                ["exception", "termination", "signal", "reason", "faultingThread", "procName"]
                    .contains { line.lowercased().contains($0) }
            }
            .prefix(6)
        FileLogger.shared.log("看门狗：崩溃报告 \(newest) 已复制到 \(target.lastPathComponent)")
        for line in interesting {
            FileLogger.shared.log("看门狗：\(line.prefix(200))")
        }
    }

    /// 初始化走完后调用（延迟几秒），清掉标记。
    static func markLaunchSucceeded() {
        try? FileManager.default.removeItem(at: markerURL)
        try? String("0").write(to: crashCountURL, atomically: true, encoding: .utf8)
    }
}
