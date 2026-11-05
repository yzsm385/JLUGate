import Foundation

/// 「能不能上网」的快捷排查：对一组站点逐层测量，然后把失败归因到具体一层。
public enum ProbeStage: String, Sendable, Equatable {
    case ok
    case dns
    case tcp
    case tls
    case http
    case cancelled

    public var human: String {
        switch self {
        case .ok: "通"
        case .dns: Copy.t("B325")
        case .tcp: Copy.t("B326")
        case .tls: Copy.t("B327")
        case .http: Copy.t("B328")
        case .cancelled: Copy.t("B329")
        }
    }
}

public struct SiteResult: Sendable, Equatable, Identifiable {
    public let host: String
    public let stage: ProbeStage
    public let httpStatus: Int?
    public let milliseconds: Int?
    public let isDomestic: Bool
    /// 校内系统（教务/通知/邮箱）
    public let isCampus: Bool
    /// 只在校园网内才能访问（邮箱在校外也能开，不算）
    public let isCampusOnly: Bool

    /// 访问范围说明（界面用）：邮箱不是校内独有。
    public var accessNote: String {
        guard isCampus else { return "" }
        return isCampusOnly ? Copy.t("B330") : Copy.t("B331")
    }

    public var id: String { host }
    public var ok: Bool { stage == .ok }

    public init(host: String, stage: ProbeStage, httpStatus: Int? = nil,
                milliseconds: Int? = nil, isDomestic: Bool, isCampus: Bool = false,
                isCampusOnly: Bool = false) {
        self.host = host
        self.stage = stage
        self.httpStatus = httpStatus
        self.milliseconds = milliseconds
        self.isDomestic = isDomestic
        self.isCampus = isCampus
        self.isCampusOnly = isCampusOnly
    }

    public var display: String {
        switch stage {
        case .ok:
            return httpStatus.map { Copy.f("B332", $0) } ?? "通"
        case .http:
            return httpStatus.map { Copy.f("B333", $0) } ?? Copy.t("B334")
        default:
            return stage.human
        }
    }
}

/// 结论：到底哪一层坏了。
public enum NetworkVerdict: Sendable, Equatable {
    case healthy
    case noInterface
    case campusAuthDown
    case dnsBroken
    case proxyBroken
    case blockedOverseas
    case tlsRejected
    case siteRefused
    /// 校内系统不通，但公网正常 → 多半不在校园网内（或需要 WebVPN）
    case campusUnreachable
    case unknown
}

public struct ReachabilityDiagnosis: Sendable, Equatable {
    public let verdict: NetworkVerdict
    public let summary: String
    public let action: String
}

public enum ReachabilityDiagnosisEngine {
    /// - Parameters:
    ///   - campusAuthReachable: 学校认证服务器（10.100.61.3）是否有回执；nil = 没测
    ///   - proxyInUse: 当前是否走代理/VPN（默认路由在虚拟网卡上）
    public static func diagnose(sites: [SiteResult],
                                campusAuthReachable: Bool?,
                                hasUsableInterface: Bool,
                                proxyInUse: Bool) -> ReachabilityDiagnosis {
        guard hasUsableInterface else {
            return .init(verdict: .noInterface,
                         summary: Copy.t("B335"),
                         action: Copy.t("B336"))
        }
        guard !sites.isEmpty else {
            return .init(verdict: .unknown, summary: Copy.t("B337"), action: Copy.t("B338"))
        }

        // 先看结果：全都通的话，校内认证服务器没回执也不影响你上网
        let ok = sites.filter(\.ok)
        if ok.count == sites.count {
            return .init(verdict: .healthy,
                         summary: Copy.t("B339"),
                         action: Copy.t("B340"))
        }
        if campusAuthReachable == false {
            return .init(verdict: .campusAuthDown,
                         summary: Copy.t("B341"),
                         action: Copy.t("B342"))
        }

        let dnsFails = sites.filter { $0.stage == .dns }.count
        let tcpFails = sites.filter { $0.stage == .tcp }.count
        let tlsFails = sites.filter { $0.stage == .tls }.count
        let httpFails = sites.filter { $0.stage == .http }.count
        let domesticOK = sites.contains { $0.isDomestic && $0.ok }
        let overseasAllFail = sites.filter { !$0.isDomestic }.allSatisfy { !$0.ok }
        let overseasCount = sites.filter { !$0.isDomestic }.count

        if dnsFails >= max(2, sites.count - 1) {
            return .init(verdict: .dnsBroken,
                         summary: Copy.t("B343"),
                         action: Copy.t("B344"))
        }
        if tlsFails >= 2 {
            return .init(verdict: .tlsRejected,
                         summary: Copy.t("B345"),
                         action: Copy.t("B346"))
        }
        if httpFails >= 2 {
            return .init(verdict: .siteRefused,
                         summary: Copy.t("B347"),
                         action: Copy.t("B348"))
        }
        if overseasAllFail, overseasCount > 0, domesticOK {
            if proxyInUse {
                return .init(verdict: .proxyBroken,
                             summary: Copy.t("B349"),
                             action: Copy.t("B350"))
            }
            return .init(verdict: .blockedOverseas,
                         summary: Copy.t("B351"),
                         action: Copy.t("B352"))
        }
        // 校内系统全挂、公网正常 → 不是代理问题，是不在校园网
        // 只有"校内独有"的系统全挂才说明不在校园网；邮箱在校外也能开，不能当证据
        let campusOnly = sites.filter(\.isCampusOnly)
        let publicSites = sites.filter { !$0.isCampus }
        if !campusOnly.isEmpty, campusOnly.allSatisfy({ !$0.ok }), publicSites.contains(where: \.ok) {
            // 邮箱在校外也能开，不能算"仅校内"；这里只点名真正的校内独有系统
            let names = campusOnly.map(\.host).joined(separator: "、")
            return .init(verdict: .campusUnreachable,
                         summary: Copy.f("B353", names),
                         action: Copy.t("B354"))
        }

        if tcpFails >= 2 {
            return .init(verdict: .proxyBroken,
                         summary: Copy.t("B355"),
                         action: proxyInUse
                            ? Copy.t("B356")
                            : Copy.t("B357"))
        }
        return .init(verdict: .unknown,
                     summary: Copy.t("B358"),
                     action: Copy.t("B359"))
    }
}
