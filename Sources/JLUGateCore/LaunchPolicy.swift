import Foundation

/// 启动时的决策：什么时候该静默自动连、什么时候才该弹向导。
///
/// 目标：**记住账号密码并且成功连过之后，用户再也不用重新填**。
/// 只有在"真的缺东西"时才打断用户：没账号、没密码、或者选了有线/JLU.PC 却还没填地址。
public enum LaunchPolicy {
    /// 是否需要弹首次向导。
    public static func shouldShowWizard(hasAccount: Bool,
                                        hasPassword: Bool,
                                        linkRequiresStaticAddresses: Bool,
                                        profileIsComplete: Bool) -> Bool {
        if !hasAccount { return true }
        if !hasPassword { return true }
        if linkRequiresStaticAddresses && !profileIsComplete { return true }
        return false
    }

    /// 是否应该静默自动连接（用户没点任何东西）。
    ///
    /// `everConnected` 只作为**记录**保留：账号密码与地址齐全、且用户开着"启动时自动连接"就尝试。
    /// 之前要求"必须成功连过一次"，导致只要第一次没连成功，之后重启永远不自动连——用户会以为程序坏了。
    public static func shouldAutoConnect(hasAccount: Bool,
                                         hasPassword: Bool,
                                         linkRequiresStaticAddresses: Bool,
                                         profileIsComplete: Bool,
                                         everConnected: Bool,   // 保留参数，不再作为门槛
                                         autoConnectEnabled: Bool) -> Bool {
        _ = everConnected
        guard autoConnectEnabled else { return false }
        guard hasAccount, hasPassword else { return false }
        if linkRequiresStaticAddresses && !profileIsComplete { return false }
        return true
    }
}
