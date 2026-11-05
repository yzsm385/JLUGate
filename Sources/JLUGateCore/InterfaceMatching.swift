import Foundation

/// 选网卡时的候选（只带和"认卡"相关的信息）。
public struct InterfaceMACCandidate: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let ipv4: String?
    /// 系统当前生效的 MAC（可能被换成私有/随机地址）
    public let currentMAC: String?
    /// 网卡出厂 MAC（学校登记的通常是这个）
    public let hardwareMAC: String?

    public init(name: String, ipv4: String?, currentMAC: String?, hardwareMAC: String?) {
        self.name = name
        self.ipv4 = ipv4
        self.currentMAC = currentMAC
        self.hardwareMAC = hardwareMAC
    }

    /// 认证应该用的那个 MAC：出厂优先。
    public var macForAuthentication: String? { hardwareMAC ?? currentMAC }

    /// 这块卡是不是登记过的那块（出厂/当前任一命中即可）。
    public func matches(_ registered: MACAddress?) -> Bool {
        guard let registered else { return false }
        return MACAddress(hardwareMAC ?? "")?.matches(registered) == true
            || MACAddress(currentMAC ?? "")?.matches(registered) == true
    }
}

public enum InterfaceMatching {
    /// 返回所有 MAC 命中的网卡名（按用户可能想用的顺序：先有线、后有地址的）。
    public static func matchedCandidates(registered: MACAddress?,
                                         candidates: [InterfaceMACCandidate]) -> [InterfaceMACCandidate] {
        guard registered != nil else { return [] }
        return candidates.filter { $0.matches(registered) }
    }

    /// 自动挑一块：正好一块命中就是它；多块命中优先有 IPv4 的；一块都没命中返回 nil。
    public static func autoSelected(registered: MACAddress?,
                                    candidates: [InterfaceMACCandidate]) -> String? {
        let matched = matchedCandidates(registered: registered, candidates: candidates)
        if matched.isEmpty { return nil }
        if matched.count == 1 { return matched[0].name }
        return matched.first(where: { $0.ipv4 != nil })?.name ?? matched[0].name
    }

    /// 给界面用的一句话（自动匹配结果 / 需要用户选）。
    public static func summary(registered: MACAddress?,
                               candidates: [InterfaceMACCandidate],
                               locked: String?) -> String {
        if let locked, candidates.contains(where: { $0.name == locked }) {
            return Copy.f("B157", locked)
        }
        guard let registered else {
            return Copy.t("B158")
        }
        let matched = matchedCandidates(registered: registered, candidates: candidates)
        switch matched.count {
        case 0:
            let listed = candidates
                .map { "\($0.name)=\($0.macForAuthentication ?? "—")" }
                .joined(separator: "、")
            return Copy.f("B159", registered, listed)
        case 1:
            return Copy.f("B160", matched[0].name, matched[0].macForAuthentication ?? "—")
        default:
            let names = matched.map(\.name).joined(separator: "、")
            return Copy.f("B161", names)
        }
    }
}
