import Foundation
import Synchronization
import JLUGateCore

#if canImport(Darwin)
import Darwin
#endif

/// 三态探针结论（PLAN §8.2）。
public enum ProbeOutcome: Sendable, Equatable {
    /// `generate_204` 真的回了 204，且 443 的 TLS 通道也通：链路真的健康。
    case healthy
    /// 被 captive portal 拦下（200 页面或 302/307 跳转）。
    case captivePortal(statusCode: Int, location: String?)
    /// 能上网关、80 端口也通，但 443 的 TLS 握手过不去。
    ///
    /// 典型成因：校园网 / 运营商在阻断**出境** TLS（2026-11-11 实测：
    /// 80 端口全通、境外 443 全部 `unexpected eof`、国内 443 正常）。
    /// 这种情况换代理节点无效——拦截按端口，不按节点。
    case tlsBlocked(detail: String)
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

    /// 国内 204 探测点（小米的联网检测地址）。
    /// gstatic / cloudflare 在吉大网络里常被拦或解析失败，用它们判断"会话还在不在"会误判；
    /// 这个在国内基本稳定，被 captive portal 拦时会返回 302/200，正好能识别"会话没了"。
    public static let cn204 = ProbeTarget(
        host: "connect.rom.miui.com",
        path: "/generate_204",
        fallbackIPs: [])
}

/// TLS 探测结论。
///
/// 只关心「加密通道通不通」，**不做完整握手、不校验证书**——目的是把
/// 「TCP 通但 TLS 被切断」和「TCP 根本连不上」区分开。这两种情况给用户的
/// 结论完全不同，见 `docs/plans/v1.5.0-probe.md` §1。
public enum TLSProbeResult: Sendable, Equatable {
    /// 收到了 TLS 记录层响应（`0x16` handshake / `0x15` alert）：加密通道可用。
    case responded
    /// TCP 连上了，但发完 ClientHello 对端直接断开（读到 EOF）。
    ///
    /// 这是「TLS 被中间设备切断」的特征：不是端口关闭（会 refused），
    /// 也不是主动拒绝（会 reset），而是收下连接后静默丢弃。
    case closedAfterHello
    /// TCP 就没连上（超时 / refused / 路由不可达）。
    case unreachable
}

/// 探针依赖的最小传输面（真实实现走 BSD，单测用假的）。
public protocol ProbeTransport: Sendable {
    func resolve(host: String, server: IPv4Address,
                 interface: InterfaceSnapshot, timeout: Duration) async throws -> [IPv4Address]
    func httpGet(ip: IPv4Address, host: String, path: String, port: UInt16,
                 interface: InterfaceSnapshot, timeout: Duration) async throws -> HTTPHead
    /// 连到 `ip:port`，发一个最小 TLS ClientHello，看对端有没有回握手记录。
    ///
    /// 不抛错：三种结论都通过返回值表达，调用方不需要区分异常类型。
    func tlsProbe(ip: IPv4Address, host: String, port: UInt16,
                  interface: InterfaceSnapshot, timeout: Duration) async -> TLSProbeResult
}

extension ProbeTransport {
    /// 默认实现：不支持 TLS 探测的传输层报告 `.unreachable`，
    /// 这样老的单测假传输不用改也能编译。
    public func tlsProbe(ip: IPv4Address, host: String, port: UInt16,
                         interface: InterfaceSnapshot, timeout: Duration) async -> TLSProbeResult {
        .unreachable
    }
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

    public init(targets: [ProbeTarget] = [.gstatic, .cloudflare, .cn204],
                transport: any ProbeTransport = BSDProbeTransport(),
                timeout: Duration = .seconds(3)) {
        self.targets = targets
        self.transport = transport
        self.timeout = timeout
    }

    /// TLS 层探测目标（**多个**，必须全部被切断才判 `tlsBlocked`）。
    ///
    /// 为什么不能只用一个：2026-11-11 实测证明，这个网络是按**目标 IP**
    /// 选择性封锁的，不是按端口。同一时刻：
    ///   github.com / fastly 段 → 80 和 443 全通
    ///   google / twitter / 8.8.8.8 / 1.1.1.1 → 80 和 443 全超时
    /// 所以单个目标失败只能说明「这个 IP 被墙」，不能说明「TLS 被拦」。
    /// 只有**所有**目标都表现为「TCP 通、发完 ClientHello 就 EOF」，
    /// 才是真正的 TLS 层拦截。
    ///
    /// 全部用字面 IP：不依赖 DNS（系统 DNS 可能被 fake-ip 劫持，PLAN §F17）。
    public static let tlsTargets: [ProbeTarget] = [
        ProbeTarget(host: "github.com", path: "/",
                    fallbackIPs: [IPv4Address("140.82.121.4")!]),
        ProbeTarget(host: "www.baidu.com", path: "/",
                    fallbackIPs: [IPv4Address("36.144.42.93")!]),
    ]

    /// 学校 DNS 不可用时按顺序回退的公共 DNS（仍然由我们自己发 UDP 查询，不用系统解析器）。
    public static let fallbackDNSServers: [IPv4Address] = [
        IPv4Address("1.1.1.1")!, IPv4Address("8.8.8.8")!,
    ]

    public func run(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome {
        var failures: [String] = []
        // 档案里的学校 DNS 优先；全部失败再用公共 DNS（很多校园 Wi-Fi 不允许访问内网 DNS）
        var serverChain = dnsServers
        if serverChain.isEmpty {
            serverChain = Self.fallbackDNSServers
        }
        for target in targets {
            // 收集**所有** DNS 服务器的解析结果，而不是只用第一个成功的。
            //
            // 2026-11-12 实测：同一个域名，不同 DNS 给出的 IP 可达性完全不同——
            //   1.1.1.1   → 142.251.150.120（境外，不可达）
            //   学校 DNS  → 120.253.253.34 （国内 CDN，204 可达）
            // 只取第一个成功的解析结果，就会因为「恰好解析到被封的 IP」
            // 而误判整条链路不通。这正是探针误报「没网」的真实原因。
            var addresses: [IPv4Address] = []
            for server in serverChain {
                if let resolved = try? await transport.resolve(host: target.host, server: server,
                                                               interface: interface, timeout: timeout),
                   !resolved.isEmpty {
                    for address in resolved where !addresses.contains(address) {
                        addresses.append(address)
                    }
                }
            }
            if addresses.isEmpty {
                addresses = target.fallbackIPs
                if !target.fallbackIPs.isEmpty {
                    failures.append("\(target.host) DNS 不通，改用内置 IP")
                }
            } else {
                // DNS 解析成功也要把内置 IP 排在后面作为最后手段：
                // 解析出来的地址可能恰好落在不可达的段（2026-11-12 实测：
                // 1.1.1.1 把 gstatic 解析到境外 IP，那个 IP 不通）。
                for address in target.fallbackIPs where !addresses.contains(address) {
                    addresses.append(address)
                }
            }
            // 每个目标最多试 3 个地址：DNS 可能给出十几个结果，逐个试会把
            // 探针拖到几十秒（真机实测 46 秒），而探针每 30 秒就要跑一轮。
            for address in addresses.prefix(3) {
                guard let head = try? await transport.httpGet(
                    ip: address, host: target.host, path: target.path, port: 80,
                    interface: interface, timeout: timeout) else {
                    failures.append("\(target.host)@\(address) 连接失败")
                    continue
                }
                switch head.statusCode {
                case 204:
                    // 80 端口通了**不等于**网就好了：2026-11-11 实测到「80 全通、
                    // 出境 443 的 TLS 全被切断」这种状态。所以还要验一层 443。
                    if let verdict = await verifyTLS(interface: interface, dnsServers: serverChain) {
                        return verdict
                    }
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

    /// 80 端口判定通过后，再验一层 443 的 TLS 通道。
    ///
    /// 返回 `nil` 表示「443 没问题，可以判定 healthy」；返回非 nil 表示
    /// 应当直接采用这个结论（目前只有 `.tlsBlocked`）。
    ///
    /// 为什么必须做这一步：`PLAN.md:107` 早就写明 `generate_204` 只能证明
    /// 「有网」，不能证明加密通道可用。2026-11-11 的真实环境里，80 端口
    /// 返回 204 而境外 443 全部被切断，探针却报「在线」——用户看到的是
    /// 「显示已连接但什么都打不开」。
    private func verifyTLS(interface: InterfaceSnapshot,
                           dnsServers: [IPv4Address]) async -> ProbeOutcome? {
        var serverChain = dnsServers
        if serverChain.isEmpty { serverChain = Self.fallbackDNSServers }

        // 判定规则：**所有**目标都「TCP 通、发完 Hello 就 EOF」才判 tlsBlocked。
        // 只要有任何一个目标正常回应，就说明 TLS 层没被整体拦截（可能只是
        // 个别 IP 被墙），此时不该误报。
        var sawClosedHost: String?
        var sawAnyResponded = false

        for target in Self.tlsTargets {
            var addresses: [IPv4Address] = []
            for server in serverChain {
                if let resolved = try? await transport.resolve(host: target.host, server: server,
                                                               interface: interface, timeout: timeout),
                   !resolved.isEmpty {
                    addresses = resolved
                    break
                }
            }
            if addresses.isEmpty { addresses = target.fallbackIPs }

            for address in addresses {
                switch await transport.tlsProbe(ip: address, host: target.host, port: 443,
                                                interface: interface, timeout: timeout) {
                case .responded:
                    sawAnyResponded = true
                case .closedAfterHello:
                    if sawClosedHost == nil { sawClosedHost = target.host }
                case .unreachable:
                    // 这个 IP 本身不可达（可能被墙）：不能证明 TLS 层被拦。
                    sawAnyResponded = true
                }
            }
        }

        // 有目标能正常回应，或没有任何目标呈现「握手被切断」→ 不报 TLS 拦截
        guard !sawAnyResponded, let host = sawClosedHost else { return nil }
        return .tlsBlocked(detail: "\(host) 等目标的 443 能建立 TCP，但 TLS 握手被切断")
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

    /// 建一条绑到指定网卡的 TCP 连接。失败抛错。
    ///
    /// 抽出来是为了让 HTTP 和 TLS 探测共用同一套「非阻塞 connect + poll」逻辑，
    /// 避免两处各写一遍超时处理（写两遍迟早会走样）。
    private static func openTCP(ip: IPv4Address, port: UInt16,
                                interface: InterfaceSnapshot, timeout: Duration) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw DrcomError.channelFailure("TCP socket() 失败") }
        do {
            try bindToInterface(fd, index: interface.index)
        } catch {
            Darwin.close(fd)
            throw error
        }

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        target.sin_addr = in_addr(s_addr: ip.uint32BE.bigEndian)

        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let connected = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else {
                Darwin.close(fd)
                throw DrcomError.channelFailure("connect 失败：\(BSDChannel.errnoText())")
            }
            // 阻塞等待可写：这里用同步 poll，调用方是 async 但底层 fd 就绪很快
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, milliseconds(timeout))
            guard ready > 0 else {
                Darwin.close(fd)
                throw DrcomError.timeout(stage: "connect")
            }
            var soError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
            guard soError == 0 else {
                Darwin.close(fd)
                throw DrcomError.channelFailure("connect 失败：\(BSDChannel.errnoText(soError))")
            }
        }
        return fd
    }

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

    // MARK: TLS 探测

    public func tlsProbe(ip: IPv4Address, host: String, port: UInt16,
                         interface: InterfaceSnapshot, timeout: Duration) async -> TLSProbeResult {
        let fd: Int32
        do {
            fd = try Self.openTCP(ip: ip, port: port, interface: interface, timeout: timeout)
        } catch {
            return .unreachable
        }
        defer { Darwin.close(fd) }

        // 发一个最小但合法的 TLS 1.2 ClientHello（带 SNI）。
        // 不完成握手：只要能收到 TLS 记录层的第一个字节，就说明加密通道没被切断。
        let hello = TLSClientHello.make(host: host)
        let sent = hello.withUnsafeBytes { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
        guard sent == hello.count else { return .closedAfterHello }

        // 关键判据（2026-11-11 实测）：
        //   recv > 0 且首字节 0x16/0x15 → 加密通道可用
        //   recv == 0（EOF）            → 连接被静默切断，就是 unexpected eof
        //   poll 超时                   → 对端没理我们，按不可达处理
        var buffer = [UInt8](repeating: 0, count: 256)
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Self.milliseconds(timeout))
        guard ready > 0 else { return .unreachable }

        let received = recv(fd, &buffer, buffer.count, 0)
        if received > 0 {
            // 0x16 = handshake，0x15 = alert（例如协议版本不对）。
            // 两者都证明「对端愿意在 TLS 层对话」，拦截不成立。
            let first = buffer[0]
            if first == 0x16 || first == 0x15 { return .responded }
            // 回了别的东西（比如明文 HTTP 错误页）：说明 443 上跑的不是 TLS，
            // 但通道本身没被切断，按 responded 处理更接近事实。
            return .responded
        }
        if received == 0 { return .closedAfterHello }
        return .unreachable
    }

    private static func milliseconds(_ duration: Duration) -> Int32 {
        let ms = duration.components.seconds * 1_000
            + duration.components.attoseconds / 1_000_000_000_000_000
        return Int32(max(1, ms))
    }
}
