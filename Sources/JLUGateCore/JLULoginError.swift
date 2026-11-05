import Foundation

/// JLU Dr.Com 登录失败码（应答 `0x05` 的第 4 字节）。
///
/// 来源：社区维护实现 jlu-drcom-ng v2.0.0 的对照表，并用本仓库抓到的
/// `05 00 00 05 15 …"ldap auth error"` 交叉核对——`0x15` 即“需要升级客户端”。
public enum JLULoginError: UInt8, Sendable, CaseIterable {
    case macCheckFailed = 0x01
    case serverBusy = 0x02
    case wrongPassword = 0x03
    case insufficientBalance = 0x04
    case accountFrozen = 0x05
    case ipMismatch = 0x07
    case macMismatch = 0x0B
    case tooManyIPs = 0x14
    case clientUpgradeRequired = 0x15
    case ipAndMACMismatch = 0x16
    case mustUseDHCP = 0x17

    public var title: String {
        switch self {
        case .macCheckFailed: "MAC 校验失败"
        case .serverBusy: "服务器忙"
        case .wrongPassword: "密码错误"
        case .insufficientBalance: "余额不足"
        case .accountFrozen: "账号被冻结"
        case .ipMismatch: "IP 不匹配"
        case .macMismatch: "MAC 不匹配"
        case .tooManyIPs: "在线设备数超限"
        case .clientUpgradeRequired: "服务器拒绝凭据（0x15）"
        case .ipAndMACMismatch: "IP 与 MAC 都不匹配"
        case .mustUseDHCP: "必须使用 DHCP"
        }
    }

    public var advice: String {
        switch self {
        case .macCheckFailed, .macMismatch, .ipAndMACMismatch:
            "本机网卡与账号绑定的不一致：确认用的是登记过的那块网卡（不是随机 MAC）。"
        case .serverBusy:
            "认证服务器过载，稍等片刻自动重试即可，不用改配置。"
        case .wrongPassword:
            "核对校园网密码；刚改过密码的话要同步更新。"
        case .insufficientBalance:
            "网费余额不足，先去充值。"
        case .accountFrozen:
            "账号被停机/冻结，需要联系网络中心。"
        case .ipMismatch:
            "本机 IP 与账号绑定不符：检查网线插的端口，或改成自动获取 IP。"
        case .tooManyIPs:
            "同时在线的设备数已达上限，先注销其它设备。"
        case .clientUpgradeRequired:
            "吉大网络里这个码通常表示密码不正确（社区实现 jlu-drcom-ng 在本地图里就是这么标注的）；"
            + "也可能随服务端升级变化。先用网页版验证密码，再去客户端重新输入。"
        case .mustUseDHCP:
            "把网卡改成「使用 DHCP 自动获取地址」再试。"
        }
    }

    /// 这个码重试有没有意义（true = 换新 salt 再试可能成功）。
    public var isWorthRetrying: Bool {
        self == .serverBusy
    }

    public static func from(code: UInt8) -> JLULoginError? {
        JLULoginError(rawValue: code)
    }
}
