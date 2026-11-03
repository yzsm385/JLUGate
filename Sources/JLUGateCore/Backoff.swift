import Foundation

/// 重连退避：`delay = min(cap, base × 2^min(attempt,5)) + random(0...jitter)`（PLAN §8.4）。
///
/// `attempt` 从 1 起。超过 `maxAttempts` 就应交回用户（`idle` + "网关无响应"），
/// 不允许无限重登——两台设备同账号互抢会形成顶号乒乓（CHECKLIST §12）。
public struct Backoff: Sendable, Equatable {
    public var base: Double
    public var cap: Double
    public var jitter: Double
    public var maxAttempts: Int

    public init(base: Double = 2, cap: Double = 60, jitter: Double = 3, maxAttempts: Int = 8) {
        self.base = base
        self.cap = cap
        self.jitter = jitter
        self.maxAttempts = maxAttempts
    }

    /// 上限部分（不含抖动），单测用来验证曲线。
    public func baseDelay(attempt: Int) -> Double {
        let exponent = min(max(attempt, 1), 5)
        return min(cap, base * pow(2, Double(exponent)))
    }

    /// 实际等待时长。`jitterFraction` 属于 `[0, 1]`，由调用方给随机数（可注入假随机）。
    public func delay(attempt: Int, jitterFraction: Double) -> Duration {
        let seconds = baseDelay(attempt: attempt) + max(0, min(1, jitterFraction)) * jitter
        return .seconds(seconds)
    }

    /// 与系统随机源耦合的便利版本。
    public func delay(attempt: Int) -> Duration {
        delay(attempt: attempt, jitterFraction: Double.random(in: 0...1))
    }

    public func shouldGiveUp(attempt: Int) -> Bool {
        attempt > maxAttempts
    }
}
