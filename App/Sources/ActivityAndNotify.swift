import AppKit
import Foundation
import UserNotifications
import JLUGateCore

/// 在线期间持有一次"别把我 App Nap 掉"的断言（PLAN §3.2）。
///
/// 只承诺"用户发起的活动"，**不阻止系统休眠**：合盖该睡就睡，醒来由
/// `DrcomEngine`/`AuthCoordinator` 重建连接（§8.3）。
@MainActor
final class ActivityKeeper {
    private var token: NSObjectProtocol?

    var isHolding: Bool { token != nil }

    func begin(reason: String = "保持校园网在线") {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: reason)
    }

    func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}

/// "失败不打扰"（PLAN §3.2）：只有**需要用户决策**的失败才发一条通知。
///
/// 认证失败（密码错）、顶号、MAC 冲突、DHCP、TUN 接管 → 通知；
/// 网关超时/退避重连 → 静默，最多在菜单栏显示。
@MainActor
enum Notifier {
    private static var authorized = false
    private static var lastKey: String?

    static func requestAuthorizationIfNeeded() {
        guard !authorized else { return }
        authorized = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyFailure(_ error: DrcomError) {
        guard error.requiresUserAction else { return }
        let key = error.userMessage
        guard key != lastKey else { return }   // 同一个原因只提醒一次
        lastKey = key

        let content = UNMutableNotificationContent()
        content.title = "JLU Gate 需要你处理"
        content.body = error.userMessage
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func resetDeduplication() {
        lastKey = nil
    }
}
