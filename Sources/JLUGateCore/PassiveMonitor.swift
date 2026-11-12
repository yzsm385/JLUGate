import Foundation

/// "只观测、不认证"的启动模式。
///
/// 场景：用户**已经**在浏览器里登录过校园网（或会话还没过期），但从来没配过我们这个 App。
/// 这时候不该一上来就逼人输账号密码——当前就是在线的，如实显示"已连接"即可。
/// 只有等到**真的需要认证**（掉线 / 被门户拦）时，才请他填一次。
public enum PassiveMonitor {
    public enum Observation: Sendable, Equatable {
        case online
        case needsAuthentication(statusCode: Int?, location: String?)
        /// 80 端口通（能到网关、认证活着），但 443 的 TLS 被切断。
        /// 必须和 `unreachable` 分开：断网要重连，这个重连也没用。
        case tlsBlocked(reason: String)
        case unreachable(reason: String)
    }

    public enum Decision: Sendable, Equatable {
        /// 显示"已连接"，不打扰用户。
        case reportOnline
        /// 需要账号密码：空闲态 + 提示填写。
        case requestCredentials
        /// 链路问题：显示失败原因，不弹向导。
        case reportOffline(String)
        /// 链路本身是好的，只是加密通道被切断：保持在线态，但标注出来。
        case reportTLSBlocked(String)
    }

    public static func decide(_ observation: Observation) -> Decision {
        switch observation {
        case .online: .reportOnline
        case .needsAuthentication: .requestCredentials
        case .tlsBlocked(let reason): .reportTLSBlocked(reason)
        case .unreachable(let reason): .reportOffline(reason)
        }
    }

    /// 什么时候该**自动**弹向导：只有"刚才还在线、现在掉了"这一次。
    /// 冷启动发现需要认证时也弹一次（用户还没配过账号，不提示他就永远连不上）；
    /// 但重复轮询不再骚扰。
    public static func shouldPromptOnNeedsAuth(wasOnline: Bool, alreadyPrompted: Bool) -> Bool {
        if alreadyPrompted { return false }
        _ = wasOnline
        return true
    }
}
