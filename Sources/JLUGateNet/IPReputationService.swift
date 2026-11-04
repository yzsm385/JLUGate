import Foundation
import JLUGateCore

/// 查出口 IP 的归属与纯净度：住宅还是机房、有没有被标记成代理。
///
/// 用两个免费接口交叉（ipinfo + ipapi.co）；拿不到 hosting/proxy 标记时，
/// 用 ASN/组织名里的云厂商关键词兜底（判定逻辑在 Core/IPPurityJudge，已单测）。
public struct IPReputationService: Sendable {
    public init() {}

    public func lookup(ip: String, cloudflareCountry: String? = nil) async -> IPReputation? {
        var country: String?
        var region: String?
        var city: String?
        var isp: String?
        var org: String?
        var asn: String?
        var hosting: Bool?
        var proxy: Bool?

        if let info = await ipinfo(ip) {
            country = info.country
            region = info.region
            city = info.city
            org = info.org
            asn = info.asn
        }
        if let api = await ipAPI(ip) {
            country = country ?? api.country
            region = region ?? api.region
            city = city ?? api.city
            isp = api.isp
            org = org ?? api.org
            asn = asn ?? api.asn
            hosting = api.hosting
            proxy = api.proxy
        }
        guard country != nil || org != nil || isp != nil else { return nil }

        return IPPurityJudge.judge(ip: ip, country: country, region: region, city: city,
                                   isp: isp, org: org, asn: asn, hosting: hosting, proxy: proxy,
                                   cloudflareCountry: cloudflareCountry)
    }

    // MARK: - ipinfo.io

    private struct IPInfo: Sendable {
        var country: String?
        var region: String?
        var city: String?
        var org: String?
        var asn: String?
    }

    private func ipinfo(_ ip: String) async -> IPInfo? {
        guard let text = await get("https://ipinfo.io/\(ip)/json") else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        var info = IPInfo()
        info.country = object["country"] as? String
        info.region = object["region"] as? String
        info.city = object["city"] as? String
        if let org = object["org"] as? String {
            info.org = org
            // ipinfo 的 org 形如 "AS4713 NTT Communications"
            if let first = org.split(separator: " ").first, first.hasPrefix("AS") {
                info.asn = String(first)
            }
        }
        return info
    }

    // MARK: - ipapi.co

    private struct IPAPI: Sendable {
        var country: String?
        var region: String?
        var city: String?
        var isp: String?
        var org: String?
        var asn: String?
        var hosting: Bool?
        var proxy: Bool?
    }

    private func ipAPI(_ ip: String) async -> IPAPI? {
        guard let text = await get("https://ipapi.co/\(ip)/json/") else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        var api = IPAPI()
        api.country = object["country_code"] as? String
        api.region = object["region"] as? String
        api.city = object["city"] as? String
        api.isp = object["org"] as? String
        api.org = object["org"] as? String
        api.asn = object["asn"] as? String
        // ipapi.co 不收 hosting/proxy 字段（付费项）；有就用
        api.hosting = object["hosting"] as? Bool
        api.proxy = object["proxy"] as? Bool
        return api
    }

    private func get(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("JLU Gate/0.1 (ip reputation)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(decoding: data.prefix(4000), as: UTF8.self)
    }
}
