import Foundation
import Testing
@testable import JLUGateCore

@Suite("代理模式判定（对照小火箭的几种模式）")
struct ProxyModeTests {
    private func facts(defaultTunnel: Bool, campusTunnel: Bool,
                       hasTunnel: Bool = true, campusIface: String? = "en0",
                       apps: [String] = ["Shadowrocket"]) -> ProxyFacts {
        ProxyFacts(hasTunnel: hasTunnel,
                   defaultRouteIsTunnel: defaultTunnel,
                   campusRouteIsTunnel: campusTunnel,
                   campusRouteInterface: campusIface,
                   proxyAppNames: apps)
    }

    @Test("全局代理：不一定失败，取决于绕路的延迟/丢包")
    func global() {
        let analysis = ProxyModeAnalyzer.analyze(facts(defaultTunnel: true, campusTunnel: true))
        #expect(analysis.mode == .global)
        #expect(analysis.summary.contains("取决于"))
        #expect(analysis.summary.contains("延迟"))
        #expect(analysis.advice.contains("配置"))
        #expect(analysis.advice.contains("10.0.0.0/8"))
        #expect(analysis.advice.contains("延迟"), "建议里要先测延迟，而不是断言必失败")
    }

    @Test("规则/配置模式：默认走代理，校园网段直连 → 认证能成功")
    func ruleSplit() {
        let analysis = ProxyModeAnalyzer.analyze(facts(defaultTunnel: true, campusTunnel: false))
        #expect(analysis.mode == .ruleSplit)
        #expect(analysis.summary.contains("en0"))
        #expect(analysis.advice.contains("保持"))
    }

    @Test("直连：没有 TUN 抢默认路由")
    func direct() {
        let analysis = ProxyModeAnalyzer.analyze(
            facts(defaultTunnel: false, campusTunnel: false, hasTunnel: false, apps: []))
        #expect(analysis.mode == .direct)
        #expect(analysis.summary.contains("不会被代理吞掉"))
    }

    @Test("TUN 开着但没接管默认路由")
    func tunnelIdle() {
        let analysis = ProxyModeAnalyzer.analyze(facts(defaultTunnel: false, campusTunnel: false))
        #expect(analysis.mode == .tunnelIdle)
        #expect(analysis.advice.contains("配置"))
    }

    @Test("和用户自述的小火箭模式做对照")
    func declaredComparison() {
        let split = facts(defaultTunnel: true, campusTunnel: false)
        #expect(ProxyModeAnalyzer.analyze(split, declared: .config).matchesDeclared == true)
        #expect(ProxyModeAnalyzer.analyze(split, declared: .proxy).matchesDeclared == false)
        #expect(ProxyModeAnalyzer.analyze(split, declared: .direct).matchesDeclared == false)

        let global = facts(defaultTunnel: true, campusTunnel: true)
        #expect(ProxyModeAnalyzer.analyze(global, declared: .proxy).matchesDeclared == true)
        #expect(ProxyModeAnalyzer.analyze(global, declared: .config).matchesDeclared == false)

        #expect(ProxyModeAnalyzer.analyze(split, declared: .unknown).matchesDeclared == nil)
    }

    @Test("检测到的代理 App 名字会出现在结论里")
    func appNames() {
        let analysis = ProxyModeAnalyzer.analyze(
            facts(defaultTunnel: true, campusTunnel: true, apps: ["Shadowrocket", "ClashX"]))
        #expect(analysis.summary.contains("Shadowrocket"))
        #expect(analysis.summary.contains("ClashX"))
    }
}
