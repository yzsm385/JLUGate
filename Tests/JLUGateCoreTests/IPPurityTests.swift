import Foundation
import Testing
@testable import JLUGateCore

@Suite("IP 纯净度")
struct IPPurityTests {
    @Test("hosting 标记 → 机房 IP，并给出提醒")
    func hosting() {
        let reputation = IPPurityJudge.judge(ip: "203.0.113.9", country: "US", region: nil, city: nil,
                                            isp: "Example Cloud", org: nil, asn: "AS64500",
                                            hosting: true, proxy: nil, cloudflareCountry: nil)
        #expect(reputation.kind == .datacenter)
        #expect(reputation.notes.contains { $0.contains("Claude") })
        #expect(reputation.summary.contains("机房"))
    }

    @Test("云厂商关键词兜底判断")
    func keyword() {
        let reputation = IPPurityJudge.judge(ip: "203.0.113.10", country: "JP", region: nil, city: nil,
                                            isp: "Amazon.com, Inc.", org: nil, asn: nil,
                                            hosting: nil, proxy: nil, cloudflareCountry: nil)
        #expect(reputation.kind == .datacenter)
    }

    @Test("小型 VPS 厂商也算机房（G-Core 实测）")
    func smallVPSHost() {
        let reputation = IPPurityJudge.judge(ip: "203.0.113.21", country: "KR", region: nil, city: nil,
                                            isp: "G-Core Labs S.A.", org: nil, asn: "AS199524",
                                            hosting: nil, proxy: nil, cloudflareCountry: nil)
        #expect(reputation.kind == .datacenter)
    }

    @Test("运营商 → 住宅 IP")
    func residential() {
        let reputation = IPPurityJudge.judge(ip: "203.0.113.11", country: "JP", region: "Tokyo",
                                            city: "Chiyoda", isp: "NTT Communications", org: nil,
                                            asn: "AS4713", hosting: false, proxy: false,
                                            cloudflareCountry: "JP")
        #expect(reputation.kind == .residential)
        #expect(reputation.notes.isEmpty)
        #expect(reputation.summary.contains("NTT"))
    }

    @Test("国家与 Cloudflare 机房不一致 → 广播/中转提示")
    func broadcast() {
        let reputation = IPPurityJudge.judge(ip: "203.0.113.12", country: "SG", region: nil, city: nil,
                                            isp: "NTT", org: nil, asn: nil,
                                            hosting: false, proxy: nil, cloudflareCountry: "JP")
        #expect(reputation.notes.contains { $0.contains("广播") })
    }

    @Test("被标记代理 + 中国大陆出口都要提示")
    func flags() {
        let reputation = IPPurityJudge.judge(ip: "203.0.113.13", country: "CN", region: nil, city: nil,
                                            isp: "China Telecom", org: nil, asn: nil,
                                            hosting: false, proxy: true, cloudflareCountry: nil)
        #expect(reputation.notes.contains { $0.contains("代理") })
        #expect(reputation.notes.contains { $0.contains("中国大陆") })
    }
}
