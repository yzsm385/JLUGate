import Foundation

/// 状态"粘性"：刚连上不久、且网络确实可达时，不要因为引擎一次失败就把图标打回未连接。
///
/// 真机上出现过：灰（启动）→ 绿（已连接）→ 红（未连接），但网络一直是通的。
/// 原因是引擎重试/端口被官方客户端占用时会报失败，而界面直接照着 failed 画。
public enum StatusStickiness {
    /// 判定"这次失败要不要当成仍在在线"。
    /// - Parameters:
    ///   - lastOnlineAt: 最近一次确认在线的时间
    ///   - lastHealthyProbeAt: 最近一次真实探测成功的时间
    ///   - now: 当前时间
    ///   - grace: 宽限期（默认 120 秒）
    public static func treatFailureAsOnline(lastOnlineAt: Date?,
                                            lastHealthyProbeAt: Date?,
                                            now: Date = Date(),
                                            grace: TimeInterval = 120) -> Bool {
        guard let lastHealthy = lastHealthyProbeAt else { return false }
        guard now.timeIntervalSince(lastHealthy) <= grace else { return false }
        // 只要最近探测是通的，就认为会话仍然有效（哪怕从没在线过，例如官方客户端在管）
        if let lastOnline = lastOnlineAt {
            return now.timeIntervalSince(lastOnline) <= grace
        }
        return true
    }
}
