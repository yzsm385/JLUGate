import Foundation
import Testing
@testable import JLUGateCore

@Suite("网络体检判定")
struct InspectionTests {
    @Test("出口与本机相同 → 没走代理")
    func sameExit() {
        #expect(InspectionVerdict.ipHint(country: "CN", sameAsLocal: true).contains("没有走代理"))
        #expect(InspectionVerdict.ipHint(country: "JP", sameAsLocal: false).contains("JP"))
    }

    @Test("WebRTC：拿到地址就说会暴露；没回执说明被挡住反而安全")
    func webRTC() {
        let leak = WebRTCSample(publicIP: "203.0.113.9", port: 5000, server: "stun",
                                latencyMilliseconds: 20, note: "")
        #expect(InspectionVerdict.webRTCHint(leak, localIP: "203.0.113.9").contains("暴露"))
        #expect(InspectionVerdict.webRTCHint(leak, localIP: "10.0.0.2").contains("浏览器"))

        let blocked = WebRTCSample(publicIP: nil, port: nil, server: "stun",
                                   latencyMilliseconds: nil, note: "")
        #expect(InspectionVerdict.webRTCHint(blocked, localIP: "10.0.0.2").contains("不会泄漏"))
    }

    @Test("人机验证：区分全挂/被挑战/正常")
    func captcha() {
        let blocked = EndpointCheck(name: "a", url: "", state: .blocked)
        #expect(InspectionVerdict.captchaHint([blocked, blocked]).contains("加载不出来"))

        let challenged = EndpointCheck(name: "a", url: "", state: .challenge)
        #expect(InspectionVerdict.captchaHint([challenged]).contains("重点照顾"))

        let ok = EndpointCheck(name: "a", url: "", state: .ok)
        #expect(InspectionVerdict.captchaHint([ok, ok]).contains("没被针对"))
    }

    @Test("DNS 泄漏：出口不同要如实说")
    func dnsSummary() {
        let same = DNSLeakSample(systemResolver: "10.0.0.1", systemEgress: "1.2.3.4",
                                 publicEgress: "1.2.3.4", hijackSuspected: false)
        #expect(same.summary.contains("一致"))

        let different = DNSLeakSample(systemResolver: "10.0.0.1", systemEgress: "1.2.3.4",
                                      publicEgress: "5.6.7.8", hijackSuspected: false)
        #expect(different.summary.contains("两套路"))

        let none = DNSLeakSample(systemResolver: nil, systemEgress: nil,
                                 publicEgress: nil, hijackSuspected: false)
        #expect(none.summary.contains("拦"))
    }
}
