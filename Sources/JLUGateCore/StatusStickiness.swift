import Foundation

/// 状态"粘性"：决定"引擎报失败时，界面要不要变红"。
///
/// 规则只有一条——**最后一次真实探测成功，才是绿；最后一次探测失败，才变红**。
/// 引擎的失败（端口被占、重连中、服务器回绝）不足以推翻"网络实际可用"这个事实：
/// 真机上就出现过 灰 → 绿 → 红 的乱跳，而网络一直是通的。
public struct StatusStickiness: Sendable {
    /// 最近一次探测成功
    public var lastHealthyProbeAt: Date?
    /// 最近一次探测失败
    public var lastFailedProbeAt: Date?
    /// 宽限期：这么久没有新的探测结果，才允许按引擎状态显示
    public var grace: TimeInterval

    public init(lastHealthyProbeAt: Date? = nil, lastFailedProbeAt: Date? = nil,
                grace: TimeInterval = 600) {
        self.lastHealthyProbeAt = lastHealthyProbeAt
        self.lastFailedProbeAt = lastFailedProbeAt
        self.grace = grace
    }

    /// 引擎报失败时，是否仍应显示为在线。
    public func shouldStayOnline(now: Date = Date()) -> Bool {
        guard let healthy = lastHealthyProbeAt else { return false }
        // 最近一次探测是失败的 → 允许变红
        if let failed = lastFailedProbeAt, failed > healthy { return false }
        // 探测结果太旧 → 不再坚持
        return now.timeIntervalSince(healthy) <= grace
    }
}
