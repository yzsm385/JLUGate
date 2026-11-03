import Foundation

/// "能不能直接用系统当前读数当静态参数"的判断。
///
/// 关键前提（PLAN §9.1 反复强调）：**DHCP 分到的地址一定不能照抄**。
/// 但如果系统本来就配置成"手动"，那这些读数就是用户/学校手填进去的那一份，
/// 直接拿来用是安全的——所以只在这种情况才自动填。
public struct NetworkParameterSuggestion: Sendable, Equatable {
    public var ip: String?
    public var mask: String?
    public var gateway: String?
    public var dns: [String]
    public var mac: String?
    /// true = 这些值可以直接用（系统是手动配置）
    public var isTrustworthy: Bool
    public var reason: String

    public var hasUsableValues: Bool {
        isTrustworthy && !(ip ?? "").isEmpty
    }
}

public enum ParameterSuggester {
    /// - Parameters:
    ///   - configMethod: `ipconfig getsummary` 里的 ConfigMethod（Manual / DHCP …）
    ///   - defaultGateway: `route get default` 的网关
    ///   - dns: 系统 DNS（仅用于展示/填充，探针仍自己发查询）
    public static func suggest(ip: String?, mask: String?, mac: String?,
                               configMethod: String?,
                               defaultGateway: String?,
                               dns: [String]) -> NetworkParameterSuggestion {
        let method = (configMethod ?? "").lowercased()
        let manual = method == "manual"

        guard manual else {
            return NetworkParameterSuggestion(
                ip: nil, mask: nil, gateway: nil, dns: dns, mac: nil,
                isTrustworthy: false,
                reason: method.isEmpty
                    ? "读不到这块网卡的配置方式；请手动照抄学校分配的地址，不要用 DHCP 分到的。"
                    : "这块网卡当前是 \(configMethod ?? "自动")，地址是自动分配的，**不能**当静态参数用。请手动照抄。")
        }

        guard let ip, !ip.isEmpty else {
            return NetworkParameterSuggestion(
                ip: nil, mask: mask, gateway: defaultGateway, dns: dns, mac: mac,
                isTrustworthy: false, reason: "系统是手动配置，但这块网卡还没有 IPv4 地址。")
        }

        return NetworkParameterSuggestion(
            ip: ip, mask: mask, gateway: defaultGateway, dns: dns, mac: mac,
            isTrustworthy: true,
            reason: "这块网卡当前是**手动配置**，以下读数就是本机实际在用的静态参数，可直接使用（建议与学校通知单核对一眼）。")
    }
}
