import Foundation

/// 各数据源对同一个 IP 的判断（多源交叉，避免单一库偏差）。
public struct GeoSourceSample: Sendable, Equatable, Identifiable {
    public let source: String      // ipinfo / ipapi / ipwho / BiliBili / IP2Location / MaxMind
    public let country: String?
    public let region: String?
    public let city: String?
    public let isp: String?
    public let asn: String?
    public var id: String { source }

    public init(source: String, country: String?, region: String?,
                city: String?, isp: String?, asn: String?) {
        self.source = source
        self.country = country
        self.region = region
        self.city = city
        self.isp = isp
        self.asn = asn
    }

    public var short: String {
        [country, region, city].compactMap { $0 }.joined(separator: "/") + " · " + (isp ?? "-")
    }
}

public struct GeoConsensus: Sendable, Equatable {
    public let ip: String
    public let samples: [GeoSourceSample]
    /// 各源给出的国家（去重后）
    public let countries: [String]
    /// 主口径：多数国家 + 多数 ISP
    public let country: String?
    public let city: String?
    public let isp: String?
    /// 是否出现"多源国家不一致"
    public let countryDisagreement: Bool
}

public enum GeoConsensusEngine {
    public static func combine(ip: String, samples: [GeoSourceSample]) -> GeoConsensus {
        // 各源写法不同（JP / 日本 / Japan），先统一成国家码再比较
        let normalized = samples.compactMap { sample in sample.country.map { normalizeCountry($0) } }
        let countries = unique(normalized)
        let cities = unique(samples.compactMap { $0.city })
        let isps = unique(samples.compactMap { $0.isp })

        let country = mostCommon(normalized)
        let city = mostCommon(samples.compactMap { $0.city })
        let isp = mostCommon(isps)

        return GeoConsensus(ip: ip, samples: samples,
                            countries: countries,
                            country: country, city: city, isp: isp,
                            countryDisagreement: countries.count > 1)
    }

    /// 国家名归一化：两字母代码直接用；常见中文/英文名映射到 ISO 代码。
    public static func normalizeCountry(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // 只有 ASCII 的两字母才是国家码；"日本"这种两字中文不能走这条捷径
        if trimmed.count == 2, trimmed.allSatisfy({ $0.isASCII && $0.isLetter }) {
            return trimmed.uppercased()
        }
        let table: [String: String] = [
            "中国": "CN", "中国大陆": "CN", "china": "CN",
            "日本": "JP", "japan": "JP",
            "韩国": "KR", "南韩": "KR", "korea": "KR", "south korea": "KR",
            "新加坡": "SG", "singapore": "SG",
            "美国": "US", "united states": "US",
            "香港": "HK", "hong kong": "HK",
            "台湾": "TW", "taiwan": "TW",
            "英国": "GB", "united kingdom": "GB",
            "德国": "DE", "germany": "DE",
            "俄罗斯": "RU", "russia": "RU",
            "加拿大": "CA", "canada": "CA",
            "澳大利亚": "AU", "australia": "AU",
            "荷兰": "NL", "netherlands": "NL",
            "法国": "FR", "france": "FR",
        ]
        return table[trimmed.lowercased()] ?? trimmed.uppercased()
    }

    static func mostCommon(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }

    static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

/// DNS 出口与 IP 出口是否"同一个地方"。
///
/// 风控系统经常比对这两者：IP 在东京、DNS 解析却在新加坡，
/// 就会被标成"代理/异常"，比单纯的机房 IP 更容易触发封禁。
public struct DNSIPAlignment: Sendable, Equatable {
    public enum Verdict: String, Sendable, Equatable {
        case sameAddress      // 完全同一个 IP
        case sameCountry      // 同国家
        case differentCountry // 不同国家 → 高风险
        case unknown
    }

    public let verdict: Verdict
    public let ipCountry: String?
    public let dnsCountry: String?
    public let explanation: String
}

public enum DNSIPAlignmentEngine {
    public static func align(ip: String, ipCountry: String?,
                             dnsEgress: String?, dnsCountry: String?) -> DNSIPAlignment {
        guard let dnsEgress else {
            return .init(verdict: .unknown, ipCountry: ipCountry, dnsCountry: nil,
                         explanation: Copy.t("P114"))
        }
        // 198.18.x（代理 fake-ip）与私网地址不是真实的解析出口
        if dnsEgress.hasPrefix("198.18.") || dnsEgress.hasPrefix("127.")
            || dnsEgress.hasPrefix("10.") || dnsEgress.hasPrefix("192.168.")
            || dnsEgress.hasPrefix("172.16.") || dnsEgress.hasPrefix("169.254.") {
            return .init(verdict: .unknown, ipCountry: ipCountry, dnsCountry: dnsCountry,
                         explanation: Copy.f("P115", dnsEgress)
                            + Copy.t("P116"))
        }
        if dnsEgress == ip {
            return .init(verdict: .sameAddress, ipCountry: ipCountry, dnsCountry: dnsCountry,
                         explanation: Copy.t("P117"))
        }
        guard let ipCountry, let dnsCountry else {
            return .init(verdict: .unknown, ipCountry: ipCountry, dnsCountry: dnsCountry,
                         explanation: Copy.t("P118"))
        }
        if ipCountry.uppercased() == dnsCountry.uppercased() {
            return .init(verdict: .sameCountry, ipCountry: ipCountry, dnsCountry: dnsCountry,
                         explanation: Copy.f("P119", dnsCountry, ipCountry))
        }
        return .init(verdict: .differentCountry, ipCountry: ipCountry, dnsCountry: dnsCountry,
                     explanation: Copy.f("P120", dnsCountry, ipCountry)
                        + Copy.t("P121"))
    }
}
