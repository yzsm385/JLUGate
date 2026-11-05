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
        case .direct: Copy.t("B301")
        case .ruleSplit: Copy.t("B302")
        case .global: Copy.t("B303")
        case .tunnelIdle: Copy.t("B304")
        case .unknown: Copy.t("B305")
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
        case .unknown: Copy.t("B306")
        case .config: Copy.t("B307")
        case .proxy: Copy.t("B308")
        case .direct: Copy.t("B309")
        case .scene: Copy.t("B310")
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
        let appText = apps.map { Copy.f("B311", $0) } ?? ""
        switch mode {
        case .direct:
            return Copy.f("B312", appText)
        case .ruleSplit:
            return Copy.f("B313", facts.campusRouteInterface ?? "物理网卡", appText)
                + Copy.t("B314")
                + Copy.t("B315")
        case .global:
            return Copy.f("B316", appText)
                + Copy.t("B317")
        case .tunnelIdle:
            return Copy.f("B318", appText)
        case .unknown:
            return Copy.t("B319")
        }
    }

    static func advice(for mode: ProxyMode) -> String {
        switch mode {
        case .direct:
            Copy.t("B320")
        case .ruleSplit:
            Copy.t("B321")
        case .global:
            Copy.t("B322")
        case .tunnelIdle:
            Copy.t("B323")
        case .unknown:
            Copy.t("B324")
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
