import Foundation
import Synchronization
import JLUGateCore

#if canImport(Darwin)
import Darwin
#endif

/// 三态探针结论（PLAN §8.2）。
public enum ProbeOutcome: Sendable, Equatable {
    /// `generate_204` 真的回了 204：链路通、也没被门户拦。
    case healthy
    /// 被 captive portal 拦下（200 页面或 302/307 跳转）。
    case captivePortal(statusCode: Int, location: String?)
    /// 连不上（链路问题，或 DNS 与兜底 IP 全废）。
    case unreachable(reason: String)

    public var isOnline: Bool {
        if case .healthy = self { return true }
        return false
    }
}

public struct ProbeTarget: Sendable, Equatable {
    public let host: String
    public let path: String
    /// 学校 DNS 不通时用的内置字面 IP（编译期常量，可能过期，仅兜底）。
    ///
    /// 只放**确实会返回 204** 的前端地址；不要放 `1.1.1.1` 这种会回 301 的地址——
    /// 那会被误判成"被门户拦截"，比没有兜底更糟。
    public let fallbackIPs: [IPv4Address]

    public init(host: String, path: String = "/generate_204", fallbackIPs: [IPv4Address]) {
        self.host = host
        self.path = path
        self.fallbackIPs = fallbackIPs
    }

    public static let gstatic = ProbeTarget(
        host: "connectivitycheck.gstatic.com",
        fallbackIPs: [IPv4Address("142.250.185.99")!, IPv4Address("142.251.32.99")!])

    public static let cloudflare = ProbeTarget(
        host: "cp.cloudflare.com",
        fallbackIPs: [IPv4Address("104.16.132.229")!])
}

/// 探针依赖的最小传输面（真实实现走 BSD，单测用假的）。
public protocol ProbeTransport: Sendable {
    func resolve(host: String, server: IPv4Address,
                 interface: InterfaceSnapshot, timeout: Duration) async throws -> [IPv4Address]
    func httpGet(ip: IPv4Address, host: String, path: String, port: UInt16,
                 interface: InterfaceSnapshot, timeout: Duration) async throws -> HTTPHead
}

public struct HTTPHead: Sendable, Equatable {
    public let statusCode: Int?
    public let location: String?
    public let firstLine: String

    public init(statusCode: Int?, location: String?, firstLine: String) {
        self.statusCode = statusCode
        self.location = location
        self.firstLine = firstLine
    }

    /// 从原始响应头文本里解析状态码与 Location。
    public static func parse(_ text: String) -> HTTPHead {
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        let first = lines.first ?? ""
        var code: Int?
        let parts = first.split(separator: " ")
        if parts.count >= 2, let parsed = Int(parts[1]) { code = parsed }
        var location: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "location" {
                location = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return HTTPHead(statusCode: code, location: location, firstLine: first)
    }
}

/// 自带 DNS 的连通性探针。
///
/// 判定口径（PLAN §8.2）：
/// - 204 → 健康
/// - 200 / 30x → 被门户拦（302 的 Location 就是入口页）
/// - 连不上 / 超时 → 异常
public struct ConnectivityProbe: Sendable {
    public var targets: [ProbeTarget]
    public var transport: any ProbeTransport
    public var timeout: Duration

    public init(targets: [ProbeTarget] = [.gstatic, .cloudflare],
                transport: any ProbeTransport = BSDProbeTransport(),
                timeout: Duration = .seconds(3)) {
        self.targets = targets
        self.transport = transport
        self.timeout = timeout
    }

    public func run(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome {
        var failures: [String] = []
        for target in targets {
            var addresses: [IPv4Address] = []
            for server in dnsServers {
                if let resolved = try? await transport.resolve(host: target.host, server: server,
                                                               interface: interface, timeout: timeout),
                   !resolved.isEmpty {
                    addresses = resolved
                    break
                }
            }
            if addresses.isEmpty {
                addresses = target.fallbackIPs
                if !target.fallbackIPs.isEmpty {
                    failures.append("\(target.host) DNS 不通，改用内置 IP")
                }
            }
            for address in addresses {
                guard let head = try? await transport.httpGet(
                    ip: address, host: target.host, path: target.path, port: 80,
                    interface: interface, timeout: timeout) else {
                    failures.append("\(target.host)@\(address) 连接失败")
                    continue
                }
                switch head.statusCode {
                case 204:
                    return .healthy
                case let code? where code == 200 || (300..<400).contains(code):
                    return .captivePortal(statusCode: code, location: head.location)
                default:
                    failures.append("\(target.host)@\(address) 返回 \(head.statusCode.map(String.init) ?? "?")")
                }
            }
        }
        return .unreachable(reason: failures.isEmpty ? "没有可用的探针目标" : failures.joined(separator: "；"))
    }
}

// MARK: - BSD 传输实现

/// 用 BSD socket 实现：DNS 走 UDP 53（绑物理口），HTTP 走 TCP 直连字面 IP。
///
/// 全程 `IP_BOUND_IF` + 直连字面 IP，绕过系统 DNS 与默认路由（PLAN §8.2 的硬要求）。
public struct BSDProbeTransport: ProbeTransport {
    public init() {}

    public func resolve(host: String, server: IPv4Address,
                        interface: InterfaceSnapshot, timeout: Duration) async throws -> [IPv4Address] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw DrcomError.channelFailure("DNS socket() 失败") }
        defer { Darwin.close(fd) }
        try Self.bindToInterface(fd, index: interface.index)

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UInt16(53).bigEndian
        target.sin_addr = in_addr(s_addr: server.uint32BE.bigEndian)

        let id = UInt16.random(in: .min ... .max)
        let query = DNSPacket.makeQuery(name: host, id: id)
        let sent = query.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(fd, buffer.baseAddress, buffer.count, 0, $0,
                                  socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == query.count else { throw DrcomError.channelFailure("DNS sendto 失败") }

        var reply = [UInt8](repeating: 0, count: 1500)
        let received = try await Self.waitReadable(fd, timeout: timeout, stage: "dns") { fd in
            recv(fd, &reply, reply.count, 0)
        }
        guard received > 0 else { throw DrcomError.timeout(stage: "dns") }
        let addresses = try DNSPacket.parseARecords(Array(reply[0..<received]))
        guard !addresses.isEmpty else { throw DrcomError.malformed("DNS 没有 A 记录：\(host)") }
        return addresses
    }

    public func httpGet(ip: IPv4Address, host: String, path: String, port: UInt16,
                        interface: InterfaceSnapshot, timeout: Duration) async throws -> HTTPHead {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw DrcomError.channelFailure("TCP socket() 失败") }
        defer { Darwin.close(fd) }
        try Self.bindToInterface(fd, index: interface.index)

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        target.sin_addr = in_addr(s_addr: ip.uint32BE.bigEndian)

        // 非阻塞 connect + poll，才能给出可判定的超时
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let connected = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else {
                throw DrcomError.channelFailure("connect 失败：\(BSDChannel.errnoText())")
            }
            _ = try await Self.waitWritable(fd, timeout: timeout)
            var soError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
            guard soError == 0 else {
                throw DrcomError.channelFailure("connect 失败：\(BSDChannel.errnoText(soError))")
            }
        }

        let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
        let payload = Array(request.utf8)
        let sent = payload.withUnsafeBytes { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
        guard sent == payload.count else { throw DrcomError.channelFailure("HTTP send 失败") }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = try await Self.waitReadable(fd, timeout: timeout, stage: "http") { fd in
            recv(fd, &buffer, buffer.count, 0)
        }
        guard received > 0 else { throw DrcomError.timeout(stage: "http") }
        let text = String(decoding: buffer[0..<received], as: UTF8.self)
        return HTTPHead.parse(text)
    }

    // MARK: POSIX 小工具

    private static func bindToInterface(_ fd: Int32, index: UInt32) throws {
        var value = index
        guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &value,
                         socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
            throw DrcomError.channelFailure("IP_BOUND_IF(\(index)) 失败：\(BSDChannel.errnoText())")
        }
    }

    private static func waitWritable(_ fd: Int32, timeout: Duration) async throws -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds(timeout))
        if ready == 0 { throw DrcomError.timeout(stage: "connect") }
        if ready < 0 { throw DrcomError.channelFailure("poll 失败：\(BSDChannel.errnoText())") }
        return true
    }

    private static func waitReadable(_ fd: Int32, timeout: Duration, stage: String,
                                     read: (Int32) -> Int) async throws -> Int {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds(timeout))
        if ready == 0 { throw DrcomError.timeout(stage: stage) }
        if ready < 0 { throw DrcomError.channelFailure("poll 失败：\(BSDChannel.errnoText())") }
        return read(fd)
    }

    private static func milliseconds(_ duration: Duration) -> Int32 {
        let ms = duration.components.seconds * 1_000
            + duration.components.attoseconds / 1_000_000_000_000_000
        return Int32(max(1, ms))
    }
}
