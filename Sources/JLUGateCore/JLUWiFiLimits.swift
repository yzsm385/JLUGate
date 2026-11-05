import Foundation

/// `JLU.WIFI` 的接入特性：**同时最多 3 台设备**。
///
/// 新设备（或新 IP）加入时，会把队列里**最早加入**的那台踢下线。
/// 所以"被踢"不是密码错了，也不该让用户以为客户端坏了：
/// 重进一次即可，但代价是会挤掉当前队列里最早的**另一台**设备。
public enum JLUWiFiLimits {
    public static let maxDevices = 3

    /// 会话掉线时给用户看的解释。
    public static let kickNotice = Copy.f("B410", maxDevices)

    /// 准备重进时的提醒（会踢掉谁）。
    public static let reclaimNotice = Copy.t("B411")

    /// 登录窗口顶部的说明。
    public static var portalHint: String {
        Copy.f("B412", maxDevices, reclaimNotice)
    }
}
