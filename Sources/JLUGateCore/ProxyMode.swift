import Foundation

/// 代理当前处在"哪种模式"——这是认证能不能成功的关键前提。
///
/// 判定**完全基于路由实测**（`route get default` / `route get 10.100.61.3`），
/// 不读小火箭/Clash 的配置文件，也不截屏，所以任何代理工具都适用。
public enum ProxyMode: String, Sendable, CaseIterable, Equatable {
    /// 没有 TUN 抢路由：流量都从物理网卡出去（小火箭「直连」或根本没开）
    case direct
    /// TUN 接管默认路由，但校园网段仍走物理网卡（小火箭「配置/规则」且 10/8 命中 DIRECT）
    case ruleSplit
    /// TUN 连校园网段也接管了（小火箭「全局」，或规则里没放行 10/8）——认证必然失败
    case global
    /// 有 TUN 但没接管默认路由（规则没命中，或只是开了但没生效）
    case tunnelIdle
    /// 拿不到路由信息
    case unknown

    public var title: String {
        switch self {
        case .direct: "直连（无代理接管）"
        case .ruleSplit: "代理已接管公网（校内网段仍直连）"
        case .global: "全局代理（校园网段被接管）"
        case .tunnelIdle: "TUN 已开启但未接管默认路由"
        case .unknown: "无法判断"
        }
    }
}

/// 用户在小火箭里选的那一档（仅用于"你选的"与"实测的"对照）。
public enum DeclaredProxyMode: String, Sendable, CaseIterable, Equatable {
    case unknown
    case config   // 配置
    case proxy    // 代理（全局）
    case direct   // 直连
    case scene    // 场景

    public var title: String {
        switch self {
        case .unknown: "未设置"
        case .config: "配置（规则分流）"
        case .proxy: "代理（全局）"
        case .direct: "直连"
        case .scene: "场景"
        }
    }
}

public struct ProxyFacts: Sendable, Equatable {
    public var hasTunnel: Bool
    public var defaultRouteIsTunnel: Bool
    public var campusRouteIsTunnel: Bool
    public var campusRouteInterface: String?
    /// 检测到的代理 App 名字（如 Shadowrocket / ClashX / Surge）
    public var proxyAppNames: [String]

    public init(hasTunnel: Bool, defaultRouteIsTunnel: Bool, campusRouteIsTunnel: Bool,
                campusRouteInterface: String?, proxyAppNames: [String] = []) {
        self.hasTunnel = hasTunnel
        self.defaultRouteIsTunnel = defaultRouteIsTunnel
        self.campusRouteIsTunnel = campusRouteIsTunnel
        self.campusRouteInterface = campusRouteInterface
        self.proxyAppNames = proxyAppNames
    }
}

public struct ProxyModeAnalysis: Sendable, Equatable {
    public let mode: ProxyMode
    /// 一句话结论
    public let summary: String
    /// 该怎么做（针对小火箭/Clash 的具体动作）
    public let advice: String
    /// 与用户自述模式是否一致（nil = 用户没选）
    public let matchesDeclared: Bool?
}

public enum ProxyModeAnalyzer {
    public static func analyze(_ facts: ProxyFacts,
                               declared: DeclaredProxyMode = .unknown) -> ProxyModeAnalysis {
        let mode = classify(facts)
        let analysis = ProxyModeAnalysis(mode: mode,
                                         summary: summary(for: mode, facts: facts),
                                         advice: advice(for: mode),
                                         matchesDeclared: match(mode: mode, declared: declared))
        return analysis
    }

    public static func classify(_ facts: ProxyFacts) -> ProxyMode {
        if facts.defaultRouteIsTunnel && facts.campusRouteIsTunnel { return .global }
        if facts.defaultRouteIsTunnel && !facts.campusRouteIsTunnel { return .ruleSplit }
        if !facts.defaultRouteIsTunnel && facts.hasTunnel { return .tunnelIdle }
        if !facts.defaultRouteIsTunnel { return .direct }
        return .unknown
    }

    static func summary(for mode: ProxyMode, facts: ProxyFacts) -> String {
        let apps = facts.proxyAppNames.isEmpty ? nil : facts.proxyAppNames.joined(separator: "、")
        let appText = apps.map { "（检测到：\($0)）" } ?? ""
        switch mode {
        case .direct:
            return "所有流量都从物理网卡出去\(appText)，认证包不会被代理吞掉。"
        case .ruleSplit:
            return "公网流量被代理接管，校内网段仍从 \(facts.campusRouteInterface ?? "物理网卡") 直接出去\(appText)。"
                + "注意：小火箭/Clash 即使在「全局」模式下通常也会放行内网段，"
                + "所以光看路由分不出「全局」还是「规则」——只要认证包没绕路，就是好事。"
        case .global:
            return "连校园网段也被虚拟网卡接管了\(appText)。认证包会绕一圈代理——能不能成功取决于这段绕路是否稳定："
                + "延迟低、不丢包就照样能认证；一旦代理抖动/排队，认证或保活超时就会被服务器判为中断。"
        case .tunnelIdle:
            return "有 TUN 接口，但默认路由还没被它接管\(appText)；可能规则没命中，或代理未真正生效。"
        case .unknown:
            return "拿不到路由信息，无法判断。"
        }
    }

    static func advice(for mode: ProxyMode) -> String {
        switch mode {
        case .direct:
            "无需改动。若你想通过代理上网，可以在小火箭里切到「配置」或「代理」。"
        case .ruleSplit:
            "这个状态对认证最友好：不用改。若哪天掉线，先确认代理没有把 10.0.0.0/8 也接管掉。"
        case .global:
            "全局模式下先测一下「认证通道延迟」：直连和经代理差得多、或经代理有丢包，就换成「配置」模式并把 10.0.0.0/8 设为 DIRECT（Clash: IP-CIDR,10.0.0.0/8,DIRECT）。延迟够低的话全局也能用，只是更容易被中断。"
        case .tunnelIdle:
            "如果你希望走代理，检查小火箭的「配置」是否启用、规则是否命中；只想认证的话当前状态也可以。"
        case .unknown:
            "到「网络详情」重新检测一次。"
        }
    }

    static func match(mode: ProxyMode, declared: DeclaredProxyMode) -> Bool? {
        guard declared != .unknown else { return nil }
        switch declared {
        case .direct: return mode == .direct || mode == .tunnelIdle
        // 全局 vs 规则：路由上分不出来（代理普遍放行私网），不硬判"不一致"
        case .proxy: return mode == .global ? true : (mode == .ruleSplit ? nil : false)
        case .config, .scene: return mode == .ruleSplit || mode == .direct
        case .unknown: return nil
        }
    }
}
