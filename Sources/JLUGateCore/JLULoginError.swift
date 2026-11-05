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
        case .macCheckFailed: Copy.t("E22")
        case .serverBusy: Copy.t("E23")
        case .wrongPassword: Copy.t("E24")
        case .insufficientBalance: Copy.t("E25")
        case .accountFrozen: Copy.t("E26")
        case .ipMismatch: Copy.t("E27")
        case .macMismatch: Copy.t("E28")
        case .tooManyIPs: Copy.t("E29")
        case .clientUpgradeRequired: Copy.t("E30")
        case .ipAndMACMismatch: Copy.t("E31")
        case .mustUseDHCP: Copy.t("E32")
        }
    }

    public var advice: String {
        switch self {
        case .macCheckFailed, .macMismatch, .ipAndMACMismatch:
            Copy.t("E33")
        case .serverBusy:
            Copy.t("E34")
        case .wrongPassword:
            Copy.t("E35")
        case .insufficientBalance:
            Copy.t("E36")
        case .accountFrozen:
            Copy.t("E37")
        case .ipMismatch:
            Copy.t("E38")
        case .tooManyIPs:
            Copy.t("E39")
        case .clientUpgradeRequired:
            Copy.t("E40")
            + Copy.t("E41")
        case .mustUseDHCP:
            Copy.t("E42")
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
