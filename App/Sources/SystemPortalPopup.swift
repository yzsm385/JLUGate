import AppKit

/// 关掉 macOS 的「捕获门户助手」窗口（Captive Network Assistant）。
///
/// 背景：连上 JLU.WIFI 这种需要网页认证的 Wi-Fi 时，是**系统**自己弹这个窗口，
/// 不是 App 弹的。它没有普通窗口的关闭按钮，登录成功前点右下角「完成」也经常
/// 没反应——用户看到的就是"弹出的页面关不掉"。
///
/// 系统没有公开 API 可以关它；按 bundle id 结束这个辅助进程是社区通用做法。
/// 它只是一个网页窗口，结束它**不会**断开 Wi-Fi、也不会影响已经建立的认证会话。
enum SystemPortalPopup {
    static let bundleIdentifier = "com.apple.CaptiveNetworkAssistant"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
            || NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// 返回是否真的关掉了（没找到窗口时返回 false）。
    @discardableResult
    static func dismiss() -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        var closed = false
        for app in apps {
            // terminate() 是礼貌退出；CNA 常常不理，直接 forceTerminate。
            closed = app.forceTerminate() || closed
        }
        guard !closed else { return true }

        // LaunchServices 偶尔不把 CNA 列进 runningApplications（它是 CoreServices 里的
        // 辅助进程）。兜底用 killall，按进程名结束，同样不需要管理员权限。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Captive Network Assistant"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
