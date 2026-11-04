import Foundation
import Testing
@testable import JLUGateCore

@Suite("能不能上网：分层归因")
struct ReachabilityTests {
    private func site(_ host: String, _ stage: ProbeStage,
                      status: Int? = nil, domestic: Bool = false) -> SiteResult {
        SiteResult(host: host, stage: stage, httpStatus: status, isDomestic: domestic)
    }

    private var allOK: [SiteResult] {
        [site("google.com", .ok, status: 200), site("baidu.com", .ok, status: 200, domestic: true)]
    }

    @Test("全通 → 网络正常")
    func healthy() {
        let d = ReachabilityDiagnosisEngine.diagnose(sites: allOK, campusAuthReachable: true,
                                                     hasUsableInterface: true, proxyInUse: true)
        #expect(d.verdict == .healthy)
    }

    @Test("全都通时，即使校内认证服务器没回执也不该报错")
    func healthyWinsOverCampus() {
        let d = ReachabilityDiagnosisEngine.diagnose(sites: allOK, campusAuthReachable: false,
                                                     hasUsableInterface: true, proxyInUse: true)
        #expect(d.verdict == .healthy)
    }

    @Test("没网卡 / 学校认证服务器没回执 → 不是代理的问题")
    func infrastructure() {
        let noInterface = ReachabilityDiagnosisEngine.diagnose(
            sites: allOK, campusAuthReachable: nil, hasUsableInterface: false, proxyInUse: false)
        #expect(noInterface.verdict == .noInterface)

        let failing = [site("google.com", .tcp), site("baidu.com", .ok, domestic: true)]
        let campus = ReachabilityDiagnosisEngine.diagnose(
            sites: failing, campusAuthReachable: false, hasUsableInterface: true, proxyInUse: false)
        #expect(campus.verdict == .campusAuthDown)
        #expect(campus.summary.contains("校内"))
    }

    @Test("全是 DNS 失败 → 归因 DNS")
    func dns() {
        let sites = [site("google.com", .dns), site("bing.com", .dns), site("baidu.com", .dns, domestic: true)]
        let d = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: true,
                                                     hasUsableInterface: true, proxyInUse: false)
        #expect(d.verdict == .dnsBroken)
        #expect(d.action.contains("DNS"))
    }

    @Test("能连上但握手被拒 → 归因 TLS/中间设备")
    func tls() {
        let sites = [site("google.com", .tls), site("duckduckgo.com", .tls), site("baidu.com", .ok, domestic: true)]
        let d = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: true,
                                                     hasUsableInterface: true, proxyInUse: true)
        #expect(d.verdict == .tlsRejected)
    }

    @Test("网站自己回 4xx/5xx → 归因网站")
    func refused() {
        let sites = [site("brave.com", .http, status: 503), site("bing.com", .http, status: 403)]
        let d = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: true,
                                                     hasUsableInterface: true, proxyInUse: false)
        #expect(d.verdict == .siteRefused)
    }

    @Test("校内系统全不通、公网正常 → 判定为不在校园网")
    func campusUnreachable() {
        let sites = [
            SiteResult(host: "iedu.jlu.edu.cn", stage: .dns, isDomestic: true,
                       isCampus: true, isCampusOnly: true),
            SiteResult(host: "oa.jlu.edu.cn", stage: .dns, isDomestic: true,
                       isCampus: true, isCampusOnly: true),
            SiteResult(host: "mails.jlu.edu.cn", stage: .ok, httpStatus: 200, isDomestic: true,
                       isCampus: true, isCampusOnly: false),
            site("baidu.com", .ok, status: 200, domestic: true),
            site("bing.com", .ok, status: 200),
        ]
        let d = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: nil,
                                                     hasUsableInterface: true, proxyInUse: true)
        #expect(d.verdict == .campusUnreachable)
        #expect(d.action.contains("WebVPN"))
        // 邮箱在校外也能开，结论文案不许把它算成"仅校内"
        #expect(!d.summary.contains("邮箱全不通"), "实际文案：\(d.summary)")
        #expect(d.summary.contains("邮箱校内外都能开"))
    }

    @Test("访问范围说明：邮箱=校内外都能开，教务/通知=仅校内")
    func accessNotes() {
        let mail = SiteResult(host: "mails.jlu.edu.cn", stage: .ok, isDomestic: true,
                              isCampus: true, isCampusOnly: false)
        let edu = SiteResult(host: "iedu.jlu.edu.cn", stage: .ok, isDomestic: true,
                             isCampus: true, isCampusOnly: true)
        let publicSite = site("baidu.com", .ok, status: 200, domestic: true)
        #expect(mail.accessNote == "校内外都能开")
        #expect(edu.accessNote == "仅校内网")
        #expect(publicSite.accessNote.isEmpty)
    }

    @Test("邮箱校外可访问 → 不能作为\"不在校园网\"的证据")
    func mailIsNotCampusOnly() {
        let sites = [
            SiteResult(host: "iedu.jlu.edu.cn", stage: .ok, httpStatus: 200,
                       isDomestic: true, isCampus: true, isCampusOnly: true),
            SiteResult(host: "mails.jlu.edu.cn", stage: .ok, httpStatus: 200,
                       isDomestic: true, isCampus: true, isCampusOnly: false),
            site("baidu.com", .ok, status: 200, domestic: true),
        ]
        let d = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: nil,
                                                     hasUsableInterface: true, proxyInUse: false)
        #expect(d.verdict == .healthy)
    }

    @Test("校内系统正常、公网部分不通 → 仍然按公网归因")
    func campusOkPublicFails() {
        let sites = [
            SiteResult(host: "oa.jlu.edu.cn", stage: .ok, httpStatus: 200, isDomestic: true, isCampus: true),
            site("google.com", .tcp), site("baidu.com", .ok, status: 200, domestic: true),
        ]
        let d = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: nil,
                                                     hasUsableInterface: true, proxyInUse: true)
        #expect(d.verdict == .proxyBroken)
    }

    @Test("国内通、国外全断：有无代理给不同结论")
    func overseas() {
        let sites = [site("baidu.com", .ok, domestic: true),
                     site("google.com", .tcp), site("brave.com", .tcp)]
        let withProxy = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: true,
                                                             hasUsableInterface: true, proxyInUse: true)
        #expect(withProxy.verdict == .proxyBroken)
        #expect(withProxy.summary.contains("代理"))

        let noProxy = ReachabilityDiagnosisEngine.diagnose(sites: sites, campusAuthReachable: true,
                                                           hasUsableInterface: true, proxyInUse: false)
        #expect(noProxy.verdict == .blockedOverseas)
    }
}
