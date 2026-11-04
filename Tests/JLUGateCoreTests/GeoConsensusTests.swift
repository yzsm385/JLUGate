import Foundation
import Testing
@testable import JLUGateCore

@Suite("多源归属交叉 / DNS 与 IP 是否吻合")
struct GeoConsensusTests {
    @Test("多数派国家胜出；ISP 取最常见")
    func consensus() {
        let samples = [
            GeoSourceSample(source: "ipinfo", country: "JP", region: "Tokyo", city: "Tokyo", isp: "NTT", asn: "AS4713"),
            GeoSourceSample(source: "ipapi", country: "JP", region: "Tokyo", city: "Chiyoda", isp: "NTT", asn: "AS4713"),
            GeoSourceSample(source: "BiliBili", country: "日本", region: nil, city: nil, isp: nil, asn: nil),
            GeoSourceSample(source: "ipwho", country: "JP", region: nil, city: "Tokyo", isp: "NTT Communications", asn: nil),
        ]
        let result = GeoConsensusEngine.combine(ip: "203.0.113.9", samples: samples)
        #expect(result.country == "JP")
        #expect(result.isp == "NTT")
        #expect(result.countryDisagreement == false)
        #expect(result.samples.count == 4)
    }

    @Test("多源国家不一致 → 标记出来（可能是广播 IP）")
    func disagreement() {
        let samples = [
            GeoSourceSample(source: "ipinfo", country: "SG", region: nil, city: nil, isp: "A", asn: nil),
            GeoSourceSample(source: "ipapi", country: "JP", region: nil, city: nil, isp: "A", asn: nil),
            GeoSourceSample(source: "BiliBili", country: "新加坡", region: nil, city: nil, isp: nil, asn: nil),
        ]
        let result = GeoConsensusEngine.combine(ip: "203.0.113.10", samples: samples)
        #expect(result.countryDisagreement)
        #expect(result.countries.count == 2)
    }

    @Test("DNS 出口与 IP 完全一致 → 最自然")
    func sameAddress() {
        let alignment = DNSIPAlignmentEngine.align(ip: "203.0.113.9", ipCountry: "JP",
                                                   dnsEgress: "203.0.113.9", dnsCountry: "JP")
        #expect(alignment.verdict == .sameAddress)
    }

    @Test("DNS 与 IP 不同国家 → 高风险，文案要说明为什么")
    func differentCountry() {
        let alignment = DNSIPAlignmentEngine.align(ip: "203.0.113.9", ipCountry: "JP",
                                                   dnsEgress: "198.51.100.7", dnsCountry: "SG")
        #expect(alignment.verdict == .differentCountry)
        #expect(alignment.explanation.contains("封"))
    }

    @Test("同国家不同地址 → 风险较低")
    func sameCountry() {
        let alignment = DNSIPAlignmentEngine.align(ip: "203.0.113.9", ipCountry: "JP",
                                                   dnsEgress: "198.51.100.7", dnsCountry: "JP")
        #expect(alignment.verdict == .sameCountry)
    }

    @Test("拿不到 DNS 出口 → 说明无法比对")
    func noDNS() {
        let alignment = DNSIPAlignmentEngine.align(ip: "203.0.113.9", ipCountry: "JP",
                                                   dnsEgress: nil, dnsCountry: nil)
        #expect(alignment.verdict == .unknown)
    }
}
