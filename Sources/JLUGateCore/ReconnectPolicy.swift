import Foundation

/// 在线期间掉线后，要不要自己重连、隔多久重。
///
/// 真机反馈：会话断了以后 App 一直显示"已连接"，用户只能手动点「登录」或重开 App。
/// 这里把"哪些失败值得自己再试一次"定死，避免：
/// - 凭据/ MAC / IP 这类问题反复撞服务器（越试越乱）；
/// - 无限重连把服务器打成风暴（两台设备同账号互踢）。
public enum ReconnectPolicy {
    /// 最多自己重连几次就停下来等用户
    public static let maxAttempts = 6

    /// 值不值得自动重连。
    public static func shouldAutoReconnect(_ error: DrcomError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        switch error {
        case .timeout, .gatewayUnreachable, .channelFailure, .notCampusNetwork:
            return true
        default:
            // 密码错、MAC 不符、端口被占、网卡没有 IP……重试解决不了，交给用户
            return false
        }
    }

    /// 第 attempt 次（从 1 起）重连前等多久：3s、6s、12s、24s，之后 30s 封顶。
    public static func delay(attempt: Int) -> Duration {
        let exponent = min(max(attempt - 1, 0), 4)
        let seconds = min(30, 3 * (1 << exponent))
        return .seconds(seconds)
    }
}
