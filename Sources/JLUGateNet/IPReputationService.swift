import Foundation
import JLUGateCore

/// 查出口 IP 的归属与纯净度：住宅还是机房、有没有被标记成代理。
///
/// 用两个免费接口交叉（ipinfo + ipapi.co）；拿不到 hosting/proxy 标记时，
/// 用 ASN/组织名里的云厂商关键词兜底（判定逻辑在 Core/IPPurityJudge，已单测）。
public struct IPReputationService: Sendable {
    /// 可选的服务商密钥（留空就跳过对应来源，不影响其它来源）
    public struct Options: Sendable, Equatable {
        public var ip2locationKey: String
        public var maxmindAccount: String
        public var maxmindLicense: String

        public init(ip2locationKey: String = "", maxmindAccount: String = "",
                    maxmindLicense: String = "") {
            self.ip2locationKey = ip2locationKey
            self.maxmindAccount = maxmindAccount
            self.maxmindLicense = maxmindLicense
        }
    }

    public init() {}

    /// 多源交叉：ipinfo / ipapi / ipwho / BiliBili（+ 可选 IP2Location / MaxMind）。
    public func geoConsensus(ip: String, options: Options = Options()) async -> GeoConsensus {
        var samples: [GeoSourceSample] = []
        await withTaskGroup(of: GeoSourceSample?.self) { group in
            group.addTask { await self.ipinfoSample(ip) }
            group.addTask { await self.ipapiSample(ip) }
            group.addTask { await self.ipwhoSample(ip) }
            group.addTask { await self.bilibiliSample(ip) }
            if !options.ip2locationKey.isEmpty {
                group.addTask { await self.ip2locationSample(ip, key: options.ip2locationKey) }
            }
            if !options.maxmindAccount.isEmpty, !options.maxmindLicense.isEmpty {
                group.addTask {
                    await self.maxmindSample(ip, account: options.maxmindAccount,
                                             license: options.maxmindLicense)
                }
            }
            for await sample in group {
                if let sample { samples.append(sample) }
            }
        }
        let order = ["ipinfo", "ipapi", "ipwho", "BiliBili", "IP2Location", "MaxMind"]
        samples.sort { (order.firstIndex(of: $0.source) ?? 99) < (order.firstIndex(of: $1.source) ?? 99) }
        return GeoConsensusEngine.combine(ip: ip, samples: samples)
    }

    // MARK: 各来源

    private func ipinfoSample(_ ip: String) async -> GeoSourceSample? {
        guard let text = await get("https://ipinfo.io/\(ip)/json"),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        return GeoSourceSample(source: "ipinfo",
                               country: object["country"] as? String,
                               region: object["region"] as? String,
                               city: object["city"] as? String,
                               isp: object["org"] as? String,
                               asn: (object["org"] as? String)?.split(separator: " ").first.map(String.init))
    }

    private func ipapiSample(_ ip: String) async -> GeoSourceSample? {
        guard let text = await get("https://ipapi.co/\(ip)/json/"),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        return GeoSourceSample(source: "ipapi",
                               country: object["country_code"] as? String,
                               region: object["region"] as? String,
                               city: object["city"] as? String,
                               isp: object["org"] as? String,
                               asn: object["asn"] as? String)
    }

    private func ipwhoSample(_ ip: String) async -> GeoSourceSample? {
        guard let text = await get("https://ipwho.is/\(ip)"),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              (object["success"] as? Bool) != false
        else { return nil }
        let connection = object["connection"] as? [String: Any]
        return GeoSourceSample(source: "ipwho",
                               country: object["country_code"] as? String,
                               region: object["region"] as? String,
                               city: object["city"] as? String,
                               isp: connection?["isp"] as? String,
                               asn: connection?["asn"].map { "AS\($0)" })
    }

    /// BiliBili 看到的出口（它的 IP 属地接口）。注意：B 站流量可能走直连，
    /// 与代理出口不是同一个地址——这本身就是"分流"的证据，单独展示。
    public func bilibiliZone() async -> (sample: GeoSourceSample, addr: String?)? {
        guard let text = await get("https://api.bilibili.com/x/web-interface/zone"),
              let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              (root["code"] as? Int) == 0,
              let data = root["data"] as? [String: Any]
        else { return nil }
        let sample = GeoSourceSample(source: "BiliBili",
                                     country: data["country"] as? String,
                                     region: data["province"] as? String,
                                     city: data["city"] as? String,
                                     isp: data["isp"] as? String,
                                     asn: nil)
        return (sample, data["addr"] as? String)
    }

    /// BiliBili 的"IP 属地"接口：返回它认为你所在的国家/省份/运营商。
    private func bilibiliSample(_ ip: String) async -> GeoSourceSample? {
        guard let text = await get("https://api.bilibili.com/x/web-interface/zone"),
              let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              (root["code"] as? Int) == 0,
              let data = root["data"] as? [String: Any]
        else { return nil }
        // 该接口返回的是"请求方"的属地；只在与我们自己的出口 IP 一致时采用
        let reported = data["addr"] as? String
        guard reported == nil || reported == ip || ip.isEmpty else { return nil }
        return GeoSourceSample(source: "BiliBili",
                               country: data["country"] as? String,
                               region: data["province"] as? String,
                               city: nil,
                               isp: data["isp"] as? String,
                               asn: nil)
    }

    private func ip2locationSample(_ ip: String, key: String) async -> GeoSourceSample? {
        guard let text = await get("https://api.ip2location.io/?key=\(key)&ip=\(ip)"),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        return GeoSourceSample(source: "IP2Location",
                               country: object["country_code"] as? String,
                               region: object["region_name"] as? String,
                               city: object["city_name"] as? String,
                               isp: object["as"] as? String,
                               asn: object["asn"].map { "AS\($0)" })
    }

    private func maxmindSample(_ ip: String, account: String, license: String) async -> GeoSourceSample? {
        guard let url = URL(string: "https://geoip.maxmind.com/geoip/v2.1/city/\(ip)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let credential = Data("\(account):\(license)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let country = (object["country"] as? [String: Any])?["iso_code"] as? String
        let city = (object["city"] as? [String: Any])?["names"] as? [String: Any]
        let region = (object["subdivisions"] as? [[String: Any]])?.first
            .flatMap { ($0["names"] as? [String: Any])?["en"] as? String }
        let isp = (object["traits"] as? [String: Any])?["isp"] as? String
        let autonomous = (object["traits"] as? [String: Any])?["autonomous_system_number"].map { "AS\($0)" }
        return GeoSourceSample(source: "MaxMind", country: country, region: region,
                               city: city?["en"] as? String, isp: isp, asn: autonomous)
    }

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
