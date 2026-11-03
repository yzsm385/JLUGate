import Foundation

/// Dr.Com 链路的状态（CHECKLIST §8 / PLAN §7）。
///
/// 只表达"对外可见的状态"，不携带内部任务；epoch 与任务管理在 `DrcomEngine`。
public enum AuthState: Sendable, Equatable {
    case idle
    case discovering
    case challenging
    case authenticating
    case online
    case reconnecting(attempt: Int)
    case failed(DrcomError)

    /// 便于 UI 与日志使用的稳定标识。
    public var phase: String {
        switch self {
        case .idle: "idle"
        case .discovering: "discovering"
        case .challenging: "challenging"
        case .authenticating: "authenticating"
        case .online: "online"
        case .reconnecting: "reconnecting"
        case .failed: "failed"
        }
    }

    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .discovering, .challenging, .authenticating, .reconnecting: true
        default: false
        }
    }

    /// 合法转移表。非法转移是**编码错误**，引擎里用 `assert`/日志暴露，绝不静默接受。
    public func canTransition(to next: AuthState) -> Bool {
        // 任何状态都允许"用户手动下线"与"进入失败态"（失败必须可见）。
        if case .idle = next { return true }
        if case .failed = next { return true }

        switch (self, next) {
        case (.idle, .discovering),
             (.idle, .challenging):
            return true
        case (.discovering, .challenging),
             (.discovering, .reconnecting):
            return true
        case (.challenging, .authenticating),
             (.challenging, .reconnecting):
            return true
        case (.authenticating, .online),
             (.authenticating, .reconnecting):
            return true
        case (.online, .reconnecting):
            return true
        case (.reconnecting, .discovering),
             (.reconnecting, .challenging),
             (.reconnecting, .reconnecting):
            return true
        case (.failed, .discovering),
             (.failed, .challenging):
            return true
        default:
            return false
        }
    }
}
