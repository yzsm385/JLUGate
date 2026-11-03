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
    public static func shouldAutoConnect(hasAccount: Bool,
                                         hasPassword: Bool,
                                         linkRequiresStaticAddresses: Bool,
                                         profileIsComplete: Bool,
                                         everConnected: Bool,
                                         autoConnectEnabled: Bool) -> Bool {
        guard autoConnectEnabled, everConnected else { return false }
        guard hasAccount, hasPassword else { return false }
        if linkRequiresStaticAddresses && !profileIsComplete { return false }
        return true
    }
}
