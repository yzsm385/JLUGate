import Foundation

/// 出口 IP 的"纯净度"：住宅 IP 还是机房 IP、有没有被标记成代理。
///
/// 这类判定在你访问 Claude / 银行 / 流媒体时最关键：机房 IP（尤其公有云段）
/// 被拒的概率远高于住宅 IP。这里把可获取的信号汇总成一句人话。
public struct IPReputation: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case residential      // 住宅/运营商
        case datacenter       // 机房/云厂商
        case mobile
        case unknown
    }

    public let ip: String
    public let country: String?
    public let region: String?
    public let city: String?
    public let isp: String?
    public let org: String?
    public let asn: String?
    /// ip-api 的 hosting 标记（机房）
    public let hosting: Bool?
    /// ip-api 的 proxy 标记（公开代理/VPN）
    public let proxy: Bool?
    public let kind: Kind
    /// 旁证：例如"IP 国家与 Cloudflare 机房国家不一致，可能是广播/中转 IP"
    public let notes: [String]

    public init(ip: String, country: String?, region: String?, city: String?,
                isp: String?, org: String?, asn: String?,
                hosting: Bool?, proxy: Bool?, kind: Kind, notes: [String]) {
        self.ip = ip
        self.country = country
        self.region = region
        self.city = city
        self.isp = isp
        self.org = org
        self.asn = asn
        self.hosting = hosting
        self.proxy = proxy
        self.kind = kind
        self.notes = notes
    }

    public var kindTitle: String {
        switch kind {
        case .residential: Copy.t("P89")
        case .datacenter: Copy.t("P90")
        case .mobile: Copy.t("P91")
        case .unknown: Copy.t("P92")
        }
    }

    /// 一句话结论 + 为什么
    public var summary: String {
        var head = kindTitle
        if proxy == true { head += Copy.t("P93") }
        let place = [city, region, country].compactMap { $0 }.joined(separator: " / ")
        let who = [isp, org].compactMap { $0 }.first
        var parts = [head]
        if !place.isEmpty { parts.append(place) }
        if let who { parts.append(who) }
        if let asn { parts.append(asn) }
        return parts.joined(separator: " · ")
    }
}

public enum IPPurityJudge {
    /// 常见云厂商/机房关键词（用于在缺少 hosting 标记时兜底判断）。
    static let datacenterKeywords = [
        "amazon", "aws", "google", "microsoft", "azure", "digitalocean", "linode",
        "vultr", "hetzner", "ovh", "oracle", "alibaba", "aliyun", "tencent", "cloud",
        "hosting", "data center", "datacenter", "server", "colo", "leaseweb",
        "contabo", "scaleway", "upcloud", "kamatera", "choopa", "frantech",
        // 常见的小型 VPS / 机房（实测会用到的）
        "g-core", "gcore", "m247", "aeza", "vdsina", "hostkey", "timeweb",
        "selectel", "netcup", "leaseweb", "servers.com", "psychz", "cogent",
        "colo", "datacamp", "hostwinds", "racknerd", "buyvm", "frantech",
    ]

    public static func judge(ip: String, country: String?, region: String?, city: String?,
                            isp: String?, org: String?, asn: String?,
                            hosting: Bool?, proxy: Bool?,
                            cloudflareCountry: String?) -> IPReputation {
        let haystack = [isp, org, asn].compactMap { $0 }.joined(separator: " ").lowercased()

        var kind: IPReputation.Kind = .unknown
        if hosting == true {
            kind = .datacenter
        } else if datacenterKeywords.contains(where: haystack.contains) {
            kind = .datacenter
        } else if haystack.contains("mobile") || haystack.contains("cellular") {
            kind = .mobile
        } else if !haystack.isEmpty {
            kind = .residential
        }

        var notes: [String] = []
        if kind == .datacenter {
            notes.append(Copy.t("P94"))
        }
        if proxy == true {
            notes.append(Copy.t("P95"))
        }
        if let country, let cloudflareCountry, country.uppercased() != cloudflareCountry.uppercased() {
            notes.append(Copy.f("P96", country, cloudflareCountry))
        }
        if let country, country.uppercased() == "CN" {
            notes.append(Copy.t("P97"))
        }

        return IPReputation(ip: ip, country: country, region: region, city: city,
                            isp: isp, org: org, asn: asn,
                            hosting: hosting, proxy: proxy, kind: kind, notes: notes)
    }
}
