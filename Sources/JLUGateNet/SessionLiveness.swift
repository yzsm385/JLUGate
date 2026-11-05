import Foundation

/// 保活没回执时，判断"这条会话到底还在不在"。
///
/// 真机上踩过的坑：以前用校内 DNS / 网关 challenge 做存活判断，可**会话被网关踢掉以后**，
/// 校内 DNS 和网关照样应达（它们本来就在认证前就能访问），于是：
/// 保活无应答 → "网络实际可达" → 继续当作在线 → 永远不重登。
/// 用户看到的就是"挂着不动、网却断了"。
///
/// 所以只认 204：能真的拿到 204 才算"已认证、能上网"；
/// 被重定向/返回网页（captive portal）说明会话没了；
/// 探针完全不通时才叫"说不准"，交给调用方用校内探针兜底（避免把被拦的目标误判成断线）。
public enum SessionLiveness {
    public enum Verdict: Sendable, Equatable {
        /// 真的能上网
        case online
        /// 被门户拦下：会话已经不在了，必须重新认证
        case offline
        /// 探针完全不通（目标被拦 / 网络本身有问题），需要别的证据
        case inconclusive
    }

    public static func verdict(_ outcome: ProbeOutcome) -> Verdict {
        switch outcome {
        case .healthy: .online
        case .captivePortal: .offline
        case .unreachable: .inconclusive
        }
    }
}
