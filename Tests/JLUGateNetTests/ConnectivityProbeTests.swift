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

    /// TLS 探测结果；键是 "ip:port"。没配就当 .unreachable。
    var tlsResults: [String: TLSProbeResult] = [:]

    func tlsProbe(ip: IPv4Address, host: String, port: UInt16,
                  interface: InterfaceSnapshot, timeout: Duration) async -> TLSProbeResult {
        tlsResults["\(ip.description):\(port)"] ?? .unreachable
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
        // 1.5.0 起：80 端口 204 还要过 443 的 TLS 才算真健康
        transport.tlsResults["1.1.1.1:443"] = .responded
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

// MARK: - 1.5.0 分层判定（80 + 443）

@Suite("1.5.0 分层探针：80 通不等于网就好")
struct LayeredProbeTests {
    private func probe(_ transport: FakeProbeTransport) -> ConnectivityProbe {
        ConnectivityProbe(targets: [.gstatic], transport: transport, timeout: .seconds(1))
    }

    /// 构造假传输：80 端口通，TLS 结果同时套用到所有 TLS 探测目标。
    private func makeTransport(tls: TLSProbeResult) -> FakeProbeTransport {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.10"] = (204, nil)
        for target in ConnectivityProbe.tlsTargets {
            for ip in target.fallbackIPs {
                transport.tlsResults["\(ip.description):443"] = tls
            }
        }
        return transport
    }

    @Test("80 返回 204 且 443 的 TLS 正常 → healthy")
    func bothLayersHealthy() async {
        let outcome = await probe(makeTransport(tls: .responded))
            .run(interface: loopback, dnsServers: [IPv4Address("10.10.10.10")!])
        #expect(outcome == .healthy)
    }

    @Test("80 返回 204 但 443 的 TLS 被切断 → tlsBlocked（核心回归）")
    func tlsCutAfterHello() async {
        // 这就是 2026-11-11 实测到的状态：80 全通、出境 443 全部 unexpected eof。
        // 旧实现会返回 .healthy，让界面显示"在线"却什么都打不开。
        let outcome = await probe(makeTransport(tls: .closedAfterHello))
            .run(interface: loopback, dnsServers: [IPv4Address("10.10.10.10")!])
        guard case .tlsBlocked = outcome else {
            Issue.record("80 通但 TLS 被切断时不该判定 healthy，实际：\(outcome)")
            return
        }
    }

    @Test("tlsBlocked 不能被当成在线")
    func tlsBlockedIsNotOnline() async {
        let outcome = await probe(makeTransport(tls: .closedAfterHello))
            .run(interface: loopback, dnsServers: [IPv4Address("10.10.10.10")!])
        #expect(outcome.isOnline == false)
    }

    @Test("80 端口就不通 → unreachable，不能误报成 tlsBlocked")
    func noEgressAtAll() async {
        var transport = FakeProbeTransport()
        transport.dnsAnswers["connectivitycheck.gstatic.com"] = ["192.0.2.10"]
        transport.httpResponses["192.0.2.10"] = nil      // 连接失败
        transport.tlsResults["1.1.1.1:443"] = .closedAfterHello

        let outcome = await probe(transport)
            .run(interface: loopback, dnsServers: [IPv4Address("10.10.10.10")!])
        guard case .unreachable = outcome else {
            Issue.record("80 都不通时应该是 unreachable，实际：\(outcome)")
            return
        }
    }

    @Test("443 只是连不上（不是被切断）→ 保持 healthy，不误报")
    func tlsUnreachableKeepsHealthy() async {
        // .unreachable 可能是探针目标本身抽风，不足以断定被拦。
        // 只有明确的 closedAfterHello（TCP 通、发完 Hello 就 EOF）才判 tlsBlocked。
        let outcome = await probe(makeTransport(tls: .unreachable))
            .run(interface: loopback, dnsServers: [IPv4Address("10.10.10.10")!])
        #expect(outcome == .healthy)
    }
}

// MARK: - TLS ClientHello 构造

@Suite("TLS ClientHello 构造")
struct TLSClientHelloTests {
    @Test("带 SNI 时结构合法")
    func withSNI() {
        let hello = TLSClientHello.make(host: "example.com")
        #expect(hello.count > 40)
        #expect(hello[0] == 0x16)                      // handshake record
        // record 层版本用 0x0301（TLS 1.0 兼容写法），真正的版本在
        // ClientHello body 里（0x0303 = TLS 1.2）。这是 OpenSSL 的惯例。
        #expect(hello[1] == 0x03 && hello[2] == 0x01)
        #expect(hello[5] == 0x01)                      // ClientHello
        // record 长度字段要和实际长度对上
        let declared = Int(hello[3]) << 8 | Int(hello[4])
        #expect(declared == hello.count - 5)
    }

    @Test("空主机名时不发 SNI，但仍然结构合法")
    func withoutSNI() {
        let hello = TLSClientHello.make(host: "")
        #expect(hello[0] == 0x16)
        let declared = Int(hello[3]) << 8 | Int(hello[4])
        #expect(declared == hello.count - 5)
    }

    @Test("SNI 里能看到域名原文")
    func sniContainsHost() {
        let hello = TLSClientHello.make(host: "jlu.edu.cn")
        let text = String(decoding: hello, as: UTF8.self)
        #expect(text.contains("jlu.edu.cn"))
    }
}

// MARK: - BSD 实现的最小烟测

@Suite("BSD TLS 探测不崩")
struct BSDTLSProbeSmokeTests {
    @Test("对本机不可达地址探测，应返回 unreachable 而不是崩溃")
    func unreachableDoesNotCrash() async {
        let transport = BSDProbeTransport()
        // 用 TEST-NET-1（192.0.2.0/24，RFC 5737 保留，保证不可达）
        let result = await transport.tlsProbe(
            ip: IPv4Address("192.0.2.1")!,
            host: "example.com",
            port: 443,
            interface: loopback,
            timeout: .milliseconds(200))
        #expect(result == .unreachable)
    }
}
