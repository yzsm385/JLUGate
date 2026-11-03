import Foundation

/// 首次向导的步骤决策（纯逻辑，便于单测）。
///
/// 用户的真实心智模型：**先填账号密码（三条链路共用），再选接入方式**；
/// 只有选了需要静态地址的方式、且这台机器上还没存过，才去问 IP/掩码/网关/MAC。
public enum WizardPolicy {
    public enum Step: String, Sendable, CaseIterable, Equatable {
        case credentials
        case link
        case network
    }

    /// 这套链路是否需要静态网络参数。
    public static func requiresStaticAddresses(link: String) -> Bool {
        link == "wired" || link == "jluPC"
    }

    /// 档案里的静态参数是否已经齐了（齐了就不再问第二遍）。
    public static func profileIsComplete(ip: String?, mask: String?,
                                         gateway: String?, mac: String?) -> Bool {
        func filled(_ value: String?) -> Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return filled(ip) && filled(mask) && filled(gateway) && filled(mac)
    }

    /// 该走哪几步。
    public static func steps(link: String,
                             profileIsComplete: Bool) -> [Step] {
        var steps: [Step] = [.credentials, .link]
        if requiresStaticAddresses(link: link), !profileIsComplete {
            steps.append(.network)
        }
        return steps
    }
}
