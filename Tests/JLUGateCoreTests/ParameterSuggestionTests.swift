import Foundation
import Testing
@testable import JLUGateCore

@Suite("自动填入静态参数（只在手动配置时可信）")
struct ParameterSuggestionTests {
    @Test("系统是 DHCP：绝不自动填，并说明原因")
    func dhcpIsNotTrustworthy() {
        let suggestion = ParameterSuggester.suggest(
            ip: "192.0.2.20", mask: "255.255.255.0", mac: "02:00:00:00:00:01",
            configMethod: "DHCP", defaultGateway: "192.0.2.1", dns: ["198.18.0.2"])
        #expect(suggestion.isTrustworthy == false)
        #expect(suggestion.ip == nil, "DHCP 地址不能当静态参数")
        #expect(suggestion.reason.contains("不能"))
    }

    @Test("系统是 Manual：可以直接用，提示核对")
    func manualIsTrustworthy() {
        let suggestion = ParameterSuggester.suggest(
            ip: "192.0.2.10", mask: "255.255.255.0", mac: "02:00:00:00:00:01",
            configMethod: "Manual", defaultGateway: "192.0.2.1", dns: ["10.10.10.10"])
        #expect(suggestion.isTrustworthy)
        #expect(suggestion.hasUsableValues)
        #expect(suggestion.ip == "192.0.2.10")
        #expect(suggestion.gateway == "192.0.2.1")
        #expect(suggestion.dns == ["10.10.10.10"])
        #expect(suggestion.reason.contains("手动"))
    }

    @Test("手动但没地址：不算可用")
    func manualWithoutAddress() {
        let suggestion = ParameterSuggester.suggest(
            ip: nil, mask: nil, mac: nil, configMethod: "Manual",
            defaultGateway: nil, dns: [])
        #expect(suggestion.isTrustworthy == false)
        #expect(suggestion.hasUsableValues == false)
    }

    @Test("读不到配置方式：保守起见不填")
    func unknownMethod() {
        let suggestion = ParameterSuggester.suggest(
            ip: "192.0.2.10", mask: "255.255.255.0", mac: nil,
            configMethod: nil, defaultGateway: nil, dns: [])
        #expect(suggestion.isTrustworthy == false)
        #expect(suggestion.reason.contains("读不到"))
    }
}
