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
        case .dns: "域名解析失败"
        case .tcp: "连不上服务器"
        case .tls: "加密握手被拒"
        case .http: "服务器拒绝请求"
        case .cancelled: "超时取消"
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
        return isCampusOnly ? "仅校内网" : "校内外都能开"
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
            return httpStatus.map { "通（HTTP \($0)）" } ?? "通"
        case .http:
            return httpStatus.map { "服务器回 \($0)" } ?? "服务器拒绝"
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
                         summary: "网卡没有可用地址，等于网线没插好。",
                         action: "插好网线 / 确认这块网卡拿到了 IP。")
        }
        guard !sites.isEmpty else {
            return .init(verdict: .unknown, summary: "还没有检测结果。", action: "点「开始排查」。")
        }

        // 先看结果：全都通的话，校内认证服务器没回执也不影响你上网
        let ok = sites.filter(\.ok)
        if ok.count == sites.count {
            return .init(verdict: .healthy,
                         summary: "全部站点都通，网络正常。",
                         action: "无需处理。")
        }
        if campusAuthReachable == false {
            return .init(verdict: .campusAuthDown,
                         summary: "有站点不通，同时连学校认证服务器都没有回执——问题更可能在校内这一段。",
                         action: "先确认在校园网内（有线/JLU.PC），或稍等再试；若长时间如此，可能是学校认证服务器在维护。")
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
                         summary: "绝大多数站点都卡在「域名解析」这一步：域名没被翻译成地址。",
                         action: "换一个 DNS（例如 223.5.5.5）试试；如果开了代理，检查它的 DNS 设置有没有把查询打回本地。")
        }
        if tlsFails >= 2 {
            return .init(verdict: .tlsRejected,
                         summary: "能连上服务器，但加密握手被拒——中间有设备在拦或证书不对。",
                         action: "若开了代理，先关掉它再试；仍失败多半是网络侧的拦截。")
        }
        if httpFails >= 2 {
            return .init(verdict: .siteRefused,
                         summary: "连接和加密都成功，是网站自己回了拒绝（4xx/5xx）。",
                         action: "换个时间再试；这类问题通常与你本机、代理无关。")
        }
        if overseasAllFail, overseasCount > 0, domesticOK {
            if proxyInUse {
                return .init(verdict: .proxyBroken,
                             summary: "国内网站通、国外全不通：代理在跑，但它的出口没把流量带出去。",
                             action: "在代理里换一个节点，或看它的日志/流量是否用尽；也可以先关掉代理验证直连是否更快。")
            }
            return .init(verdict: .blockedOverseas,
                         summary: "国内网站通、国外全不通，而且没有代理在跑——这就是典型的「没开代理」。",
                         action: "需要访问境外站点时打开代理；只想校内上网则无需处理。")
        }
        // 校内系统全挂、公网正常 → 不是代理问题，是不在校园网
        // 只有"校内独有"的系统全挂才说明不在校园网；邮箱在校外也能开，不能当证据
        let campusOnly = sites.filter(\.isCampusOnly)
        let publicSites = sites.filter { !$0.isCampus }
        if !campusOnly.isEmpty, campusOnly.allSatisfy({ !$0.ok }), publicSites.contains(where: \.ok) {
            // 邮箱在校外也能开，不能算"仅校内"；这里只点名真正的校内独有系统
            let names = campusOnly.map(\.host).joined(separator: "、")
            return .init(verdict: .campusUnreachable,
                         summary: "公网站点能上，但校内系统（\(names)）不通——它们只对校内网开放；邮箱校内外都能开，不算证据。",
                         action: "如果在校外，用学校 WebVPN 再访问；在校内则先确认认证是否成功（有线/JLU.PC）。")
        }

        if tcpFails >= 2 {
            return .init(verdict: .proxyBroken,
                         summary: "多个站点连 TCP 都失败：出口这一段断了（代理或上游）。",
                         action: proxyInUse
                            ? "换代理节点；仍不行就把代理关掉，用直连确认校园网是否正常。"
                            : "确认校园网是否已认证；也可以先 ping 网关看看。")
        }
        return .init(verdict: .unknown,
                     summary: "部分站点不通，但没有集中在一个环节。",
                     action: "看下面每站的失败环节，再决定查 DNS、代理还是网站本身。")
    }
}
