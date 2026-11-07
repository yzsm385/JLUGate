import Foundation
import Darwin
import JLUGateCore

/// 「网络体检」的实际测量：出口 IP、Cloudflare、WebRTC(STUN)、DNS 泄漏、人机验证可达性。
///
/// 全部走**默认路由**（也就是浏览器会走的那条路），这样结果才代表"外界看到的你"。
public struct InspectionService: Sendable {
    public init() {}

    // MARK: 出口 IP

    public func publicIPs() async -> [PublicIPSample] {
        var samples: [PublicIPSample] = []
        if let trace = await cloudflareTrace(), let ip = trace.ip {
            samples.append(PublicIPSample(source: "Cloudflare", ip: ip))
        }
        if let text = await httpText("https://api.ipify.org").body?
            .trimmingCharacters(in: .whitespacesAndNewlines), looksLikeIP(text) {
            samples.append(PublicIPSample(source: "ipify", ip: text))
        }
        if let text = await httpText("https://ifconfig.me/ip").body?
            .trimmingCharacters(in: .whitespacesAndNewlines), looksLikeIP(text) {
            samples.append(PublicIPSample(source: "ifconfig.me", ip: text))
        }
        // 去重（同一个 IP 只留第一条来源）
        var seen: Set<String> = []
        return samples.filter { seen.insert($0.ip).inserted }
    }

    /// 规则模式下，国内域名会走直连；用一个国内 IP 回显服务看"中国出口"。
    /// 代理/全局模式下它可能只返回代理出口，所以调用方仍要按实际国家判断。
    public func chinaEgressIP() async -> String? {
        let urls = [
            "https://myip.ipip.net",
            "https://ip.cn/api/index?ip=&type=0",
            "https://www.taobao.com/help/getip.php",
        ]
        for url in urls {
            let response = await httpText(url, timeout: .seconds(5))
            guard response.status == 200, let body = response.body else { continue }
            if let ip = Self.firstIPv4(in: body), IPv4Address(ip) != nil {
                return ip
            }
        }
        return nil
    }

    private static func firstIPv4(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    public func cloudflareTrace() async -> CloudflareTrace? {
        let response = await httpText("https://www.cloudflare.com/cdn-cgi/trace")
        guard response.status == 200, let body = response.body else { return nil }
        let trace = CloudflareTrace.parse(body)
        return trace.ip == nil ? nil : trace
    }

    // MARK: WebRTC（STUN）

    public func webRTC() async -> WebRTCSample {
        let servers: [(String, UInt16)] = [("stun.l.google.com", 19302),
                                           ("stun.cloudflare.com", 3478)]
        for (host, port) in servers {
            if let result = await stunProbe(host: host, port: port) {
                return WebRTCSample(publicIP: result.ip, port: result.port,
                                    server: "\(host):\(port)",
                                    latencyMilliseconds: result.milliseconds, note: "")
            }
        }
        return WebRTCSample(publicIP: nil, port: nil, server: "stun.l.google.com:19302",
                            latencyMilliseconds: nil, note: "没有收到 STUN 回执")
    }

    // MARK: DNS 泄漏

    public func dnsLeak() async -> DNSLeakSample {
        let resolver = systemResolver()
        let systemEgress = await egressViaDNS(server: resolver)
        let publicEgress = await egressViaDNS(server: "8.8.8.8")
        let hijack = await sinkholeSuspected(server: resolver)
        return DNSLeakSample(systemResolver: resolver, systemEgress: systemEgress,
                             publicEgress: publicEgress, hijackSuspected: hijack)
    }

    // MARK: 人机验证可达性

    public func captchaChecks() async -> [EndpointCheck] {
        let targets: [(String, String)] = [
            ("Google reCAPTCHA", "https://www.google.com/recaptcha/api.js"),
            ("reCAPTCHA 国内镜像", "https://recaptcha.net/recaptcha/api.js"),
            ("Cloudflare Turnstile", "https://challenges.cloudflare.com/turnstile/v0/api.js"),
            ("Cloudflare 挑战测试页", "https://nowsecure.nl/"),
        ]
        var checks: [EndpointCheck] = []
        for (name, url) in targets {
            let started = ContinuousClock.now
            let response = await httpText(url, timeout: .seconds(8))
            let elapsed = Self.milliseconds(from: started)
            if response.status == 0 {
                checks.append(EndpointCheck(name: name, url: url, state: .blocked,
                                            latencyMilliseconds: elapsed))
                continue
            }
            let body = response.body ?? ""
            let challenged = body.contains("Just a moment")
                || body.contains("challenge-platform")
                || body.contains("cf-challenge")
                || body.contains("g-recaptcha")
            checks.append(EndpointCheck(name: name, url: url,
                                        state: challenged ? .challenge : .ok,
                                        latencyMilliseconds: elapsed,
                                        detail: "HTTP \(response.status)"))
        }
        return checks
    }

    // MARK: - HTTP

    private func httpText(_ urlString: String,
                          timeout: Duration = .seconds(6)) async -> (status: Int, body: String?) {
        guard let url = URL(string: urlString) else { return (0, nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        request.setValue("JLU Gate/0.1 (network health check)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(timeout.components.seconds)
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, String(decoding: data.prefix(4000), as: UTF8.self))
        } catch {
            return (0, nil)
        }
    }

    private func looksLikeIP(_ text: String) -> Bool {
        IPv4Address(text) != nil
    }

    // MARK: - STUN

    private func stunProbe(host: String, port: UInt16) async -> (ip: String, port: UInt16, milliseconds: Int)? {
        guard let address = Self.resolveIPv4(host) else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        target.sin_addr = in_addr(s_addr: address.uint32BE.bigEndian)

        let request = STUN.bindingRequest()
        let started = ContinuousClock.now
        let sent = request.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(fd, buffer.baseAddress, buffer.count, 0, $0,
                                  socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == request.count else { return nil }

        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, 3000) > 0 else { return nil }

        var reply = [UInt8](repeating: 0, count: 1500)
        let received = recv(fd, &reply, reply.count, 0)
        guard received > 0 else { return nil }
        guard let parsed = try? STUN.parseBindingResponse(Data(reply[0..<received])) else { return nil }
        return (parsed.mappedAddress ?? "", parsed.mappedPort ?? 0,
                Self.milliseconds(from: started))
    }

    // MARK: - DNS

    private func systemResolver() -> String? {
        let output = PortOccupancy.shell("/usr/sbin/scutil", ["--dns"])
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver[") else { continue }
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2 else { continue }
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if IPv4Address(value) != nil { return value }
        }
        return nil
    }

    /// `whoami.akamai.net` 的 A 记录返回**解析者的出口 IP**。
    private func egressViaDNS(server: String?) async -> String? {
        guard let server, let resolver = IPv4Address(server) else { return nil }
        let addresses = dnsLookup(name: "whoami.akamai.net", server: resolver)
        return addresses.first?.description
    }

    /// 解析一个必然不存在的域名：拿到地址说明有 DNS 劫持/污染。
    private func sinkholeSuspected(server: String?) async -> Bool {
        guard let server, let resolver = IPv4Address(server) else { return false }
        let name = "jl\(UUID().uuidString.prefix(8).lowercased()).does-not-exist.invalid"
        return !dnsLookup(name: name, server: resolver).isEmpty
    }

    private func dnsLookup(name: String, server: IPv4Address) -> [IPv4Address] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UInt16(53).bigEndian
        target.sin_addr = in_addr(s_addr: server.uint32BE.bigEndian)

        let id = UInt16.random(in: .min ... .max)
        let query = DNSPacket.makeQuery(name: name, id: id)
        let sent = query.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(fd, buffer.baseAddress, buffer.count, 0, $0,
                                  socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == query.count else { return [] }

        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, 2500) > 0 else { return [] }

        var reply = [UInt8](repeating: 0, count: 1500)
        let received = recv(fd, &reply, reply.count, 0)
        guard received > 0 else { return [] }
        return (try? DNSPacket.parseARecords(Array(reply[0..<received]))) ?? []
    }

    // MARK: - 工具

    private static func resolveIPv4(_ host: String) -> IPv4Address? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM,
                             ai_protocol: IPPROTO_UDP, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        var address = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        let bytes = withUnsafeBytes(of: &address.sin_addr.s_addr) { Array($0) }
        return IPv4Address(bytes.count == 4 ? "\(bytes[3]).\(bytes[2]).\(bytes[1]).\(bytes[0])" : "")
    }

    private static func milliseconds(from start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
