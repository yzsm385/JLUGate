import Foundation
import Testing
import JLUGateCore
@testable import JLUGateNet

// MARK: - 假传输

struct FakeProbeTransport: ProbeTransport {
    var dnsAnswers: [String: [String]] = [:]
    /// `(状态码, Location)`；`nil` 表示连接失败
    var httpResponses: [String: (Int?, String?)?] = [:]

    func resolve(host: String, server: IPv4Address,
                 interface: InterfaceSnapshot, timeout: Duration) async throws -> [IPv4Address] {
        guard let answers = dnsAnswers[host], !answers.isEmpty else {
            throw DrcomError.timeout(stage: "dns")
        }
        return answers.compactMap(IPv4Address.init)
    }

    func httpGet(ip: IPv4Address, host: String, path: String, port: UInt16,
                 interface: InterfaceSnapshot, timeout: Duration) async throws -> HTTPHead {
        guard let response = httpResponses[ip.description] else {
            throw DrcomError.timeout(stage: "http")
        }
        if let response {
            let firstLine = response.0.map { "HTTP/1.1 \($0) X" } ?? "HTTP/1.1 ???"
            return HTTPHead(statusCode: response.0, location: response.1, firstLine: firstLine)
        }
        throw DrcomError.channelFailure("connect refused")
    }
}

let loopback = InterfaceSnapshot(name: "en7", index: 12, ipv4: "192.0.2.10", mac: "02:00:00:00:00:01",
                                 isWireless: false, isUp: true)

@Suite("ConnectivityProbe 判定（§8.2）")
struct ConnectivityProbeTests {
    private let schoolDNS = [IPv4Address("10.10.10.10")!]

    @Test("204 → healthy")
    func healthy() async {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.10"] = (204, nil)
        let probe = ConnectivityProbe(transport: transport)
        #expect(await probe.run(interface: loopback, dnsServers: schoolDNS) == .healthy)
    }

    @Test("302 → captivePortal，且带出 Location")
    func redirected() async {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.10"] = (302, "http://10.100.61.3/login")
        let probe = ConnectivityProbe(transport: transport)
        let outcome = await probe.run(interface: loopback, dnsServers: schoolDNS)
        #expect(outcome == .captivePortal(statusCode: 302, location: "http://10.100.61.3/login"))
    }

    @Test("200 页面 → 也是 captivePortal（门户直接返页面）")
    func portalPage() async {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.10"] = (200, nil)
        let probe = ConnectivityProbe(transport: transport)
        let outcome = await probe.run(interface: loopback, dnsServers: schoolDNS)
        #expect(outcome == .captivePortal(statusCode: 200, location: nil))
    }

    @Test("DNS 挂了就回落到内置字面 IP（不能因此判定断网）")
    func fallsBackToBuiltinIPs() async {
        var transport = FakeProbeTransport()
        // 故意不提供 DNS 答案
        transport.httpResponses["142.250.185.99"] = (204, nil)
        let probe = ConnectivityProbe(targets: [.gstatic], transport: transport)
        #expect(await probe.run(interface: loopback, dnsServers: schoolDNS) == .healthy)
    }

    @Test("全部目标都不通 → unreachable，并且原因里带上了尝试记录")
    func unreachable() async {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.10"] = nil    // 连接失败
        let probe = ConnectivityProbe(targets: [.gstatic], transport: transport)
        let outcome = await probe.run(interface: loopback, dnsServers: schoolDNS)
        guard case .unreachable(let reason) = outcome else {
            Issue.record("应为 unreachable，实际 \(outcome)")
            return
        }
        #expect(reason.contains("连接失败"))
    }

    @Test("第一个目标的 IP 不通时，会试下一个 IP / 下一个目标")
    func triesNextTarget() async {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.99"]  // 不通
        transport.dnsAnswers["cp.cloudflare.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.99"] = nil
        transport.httpResponses["192.0.2.10"] = (204, nil)
        let probe = ConnectivityProbe(transport: transport)
        #expect(await probe.run(interface: loopback, dnsServers: schoolDNS) == .healthy)
    }

    @Test("HTTP 状态行解析：204 / 302 / Location")
    func httpHeadParsing() {
        let head = HTTPHead.parse("HTTP/1.1 302 Found\r\nLocation: http://portal/login\r\nConnection: close\r\n\r\n")
        #expect(head.statusCode == 302)
        #expect(head.location == "http://portal/login")
        #expect(head.firstLine == "HTTP/1.1 302 Found")

        let noHeader = HTTPHead.parse("")
        #expect(noHeader.statusCode == nil)
    }
}
