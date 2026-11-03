import Foundation
import Testing
import JLUGateCore
@testable import JLUGateNet

@Suite("RouteGuard 三层判定（§6.5）")
struct RouteGuardTests {
    let wired = InterfaceSnapshot(name: "en7", index: 12, ipv4: "192.0.2.10",
                                  mac: "02:00:00:00:00:01", isWireless: false, isUp: true)

    @Test("A 层：出口就是物理口 → 零特权直接用")
    func layerA() {
        let guarder = RouteGuard()
        let route = RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7")
        #expect(guarder.evaluate(route: route, interface: wired, helperAuthorized: false)
                == .direct(interface: "en7"))
        #expect(guarder.evaluate(route: route, interface: wired, helperAuthorized: true)
                == .direct(interface: "en7"), "已经是 A 层就别再动路由")
    }

    @Test("B 层：被 TUN 接管 + helper 已授权 → 让 helper 加 -ifscope /32")
    func layerB() {
        let guarder = RouteGuard(registeredGateway: "192.0.2.1")
        let route = RouteInfo(destination: "10.100.61.3", gateway: "198.18.0.1", interface: "utun4")
        let result = guarder.evaluate(route: route, interface: wired, helperAuthorized: true)
        #expect(result == .helper(interface: "en7", host: "10.100.61.3", gateway: "192.0.2.1"))
        #expect(result.allowsAuthentication)
    }

    @Test("C 层：被 TUN 接管但 helper 没授权 → 给可复制的命令")
    func layerC() {
        let guarder = RouteGuard(registeredGateway: "192.0.2.1")
        let route = RouteInfo(destination: "10.100.61.3", gateway: "198.18.0.1", interface: "utun4")
        let result = guarder.evaluate(route: route, interface: wired, helperAuthorized: false)
        guard case .manual(let command, let interface) = result else {
            Issue.record("应为 manual，实际 \(result)")
            return
        }
        #expect(interface == "en7")
        #expect(command == "sudo route add -host 10.100.61.3 -ifscope en7 192.0.2.1")
        #expect(result.allowsAuthentication == false, "C 层要等用户执行完才能继续")
    }

    @Test("命令里的网关取用户档案，而不是路由表里的 TUN 地址")
    func gatewayFromProfile() {
        let guarder = RouteGuard(registeredGateway: "192.0.2.1")
        let route = RouteInfo(destination: "10.100.61.3", gateway: "198.18.0.1", interface: "utun4")
        guard case .manual(let command, _) = guarder.evaluate(route: route, interface: wired,
                                                              helperAuthorized: false) else { return }
        #expect(command.contains("192.0.2.1"))
        #expect(!command.contains("198.18.0.1"))
    }

    @Test("拿不到路由 → noRoute，不认证")
    func noRoute() {
        #expect(RouteGuard().evaluate(route: nil, interface: wired, helperAuthorized: true) == .noRoute)
        let withoutExit = RouteInfo(destination: "10.100.61.3", gateway: nil, interface: nil)
        #expect(RouteGuard().evaluate(route: withoutExit, interface: wired, helperAuthorized: true) == .noRoute)
    }

    @Test("被接管但没有网关 → 给提示而不是瞎猜一条命令")
    func missingGateway() {
        let route = RouteInfo(destination: "10.100.61.3", gateway: "198.18.0.1", interface: "utun4")
        let result = RouteGuard(registeredGateway: nil).evaluate(route: route, interface: wired,
                                                                 helperAuthorized: true)
        // 路由表里的网关虽然是 TUN 的，但它是 IPv4 → 用它生成命令（并在 UI 里提示"这是代理的网关"）
        guard case .helper(_, _, let gateway) = result else {
            Issue.record("应有兜底网关，实际 \(result)")
            return
        }
        #expect(gateway == "198.18.0.1")

        let noGatewayAtAll = RouteInfo(destination: "10.100.61.3", gateway: nil, interface: "utun4")
        guard case .manual(let hint, _) = RouteGuard(registeredGateway: nil)
            .evaluate(route: noGatewayAtAll, interface: wired, helperAuthorized: true) else {
            Issue.record("应给提示")
            return
        }
        #expect(hint.contains("网关"))
    }

    @Test("物理口名判定")
    func physicalNames() {
        #expect(RouteGuard.isPhysicalInterfaceName("en0"))
        #expect(RouteGuard.isPhysicalInterfaceName("en12"))
        #expect(RouteGuard.isPhysicalInterfaceName("utun4") == false)
        #expect(RouteGuard.isPhysicalInterfaceName("en") == false)
        #expect(RouteGuard.isPhysicalInterfaceName("en7x") == false)
        #expect(RouteGuard.isPhysicalInterfaceName("en7; rm -rf /") == false)
    }
}

@Suite("helper 参数白名单（§6.6）")
struct RouteValidatorTests {
    let validator = RouteValidator()

    private var valid: RouteRequest {
        RouteRequest(host: "10.100.61.3", gateway: "192.0.2.1", interface: "en7")
    }

    @Test("合法请求通过")
    func acceptsValid() throws {
        try validator.validate(valid, interfaceGateway: "192.0.2.1")
    }

    @Test("host 不在白名单 → 拒绝")
    func rejectsForeignHost() {
        var request = valid
        request.host = "8.8.8.8"
        #expect(throws: RouteRequestError.hostNotAllowed("8.8.8.8")) {
            try validator.validate(request, interfaceGateway: nil)
        }
    }

    @Test("host 不是 IPv4 字面量（哪怕在白名单里）→ 拒绝")
    func rejectsNonLiteralHost() {
        var request = valid
        request.host = "10.100.61.3/8"
        #expect(throws: RouteRequestError.self) {
            try validator.validate(request, interfaceGateway: nil)
        }
    }

    @Test("网关注入（分号/管道/空格）→ 拒绝")
    func rejectsInjection() {
        for evil in ["192.0.2.1; rm -rf /", "192.0.2.1 | sh", "$(whoami)", "192.0.2.1\t"] {
            var request = valid
            request.gateway = evil
            #expect(throws: RouteRequestError.self) {
                try validator.validate(request, interfaceGateway: nil)
            }
        }
    }

    @Test("接口不是 enN → 拒绝（不允许给 utun/ppp/bridge 加路由）")
    func rejectsVirtualInterface() {
        for name in ["utun4", "ppp0", "bridge0", "en7; rm", "lo0"] {
            var request = valid
            request.interface = name
            #expect(throws: RouteRequestError.self) {
                try validator.validate(request, interfaceGateway: nil)
            }
        }
    }

    @Test("网关与接口当前网关不一致 → 拒绝（防止被当成万能改路由工具）")
    func rejectsGatewayMismatch() {
        #expect(throws: RouteRequestError.gatewayMismatch(
            expected: "192.0.2.2", actual: "192.0.2.1")) {
            try validator.validate(valid, interfaceGateway: "192.0.2.2")
        }
    }

    @Test("argv 里没有任何 shell 元字符拼接")
    func argvIsArray() {
        let arguments = RouteValidator.addArguments(valid)
        #expect(arguments == ["-n", "add", "-host", "10.100.61.3", "-ifscope", "en7", "192.0.2.1"])
        #expect(!arguments.contains { $0.contains(";") || $0.contains("|") })
        #expect(RouteValidator.routeToolPath == "/sbin/route")

        let remove = RouteValidator.removeArguments(host: "10.100.61.3", interface: "en7")
        #expect(remove == ["-n", "delete", "-host", "10.100.61.3", "-ifscope", "en7"])
    }
}
