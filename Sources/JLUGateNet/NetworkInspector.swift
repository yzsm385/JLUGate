import Foundation
import Darwin
import SystemConfiguration
import Synchronization
import JLUGateCore

/// 一张"比终端还清楚"的网络快照。
public struct NetworkSnapshot: Sendable, Equatable {
    public struct InterfaceRow: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let index: UInt32
        public let ipv4: String?
        public let mask: String?
        public let mac: String?
        public let linkLocal: String?
        public let isWireless: Bool
        public let isUSB: Bool
        public let isUp: Bool
        public let isDefaultRoute: Bool
        public let carriesCampusRoute: Bool
        public let hardwareName: String?
    }

    public struct TunnelRow: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let ipv4: String?
        public let ipv6: String?
        public let isUp: Bool
    }

    public let interfaces: [InterfaceRow]
    public let tunnels: [TunnelRow]
    public let defaultRoute: RouteInfo?
    public let campusRoute: RouteInfo?
    public let dnsServers: [String]
    /// 系统 DNS 里出现 198.18.x.x（代理 fake-ip）→ 说明 DNS 已被劫持
    public let dnsLooksHijacked: Bool

    /// 把快照翻译成"代理模式判定"所需的事实。
    public func proxyFacts(runningApps: [String] = []) -> ProxyFacts {
        ProxyFacts(hasTunnel: !tunnels.isEmpty,
                   defaultRouteIsTunnel: defaultRoute?.isTunnel ?? false,
                   campusRouteIsTunnel: campusRoute?.isTunnel ?? false,
                   campusRouteInterface: campusRoute?.interface,
                   proxyAppNames: runningApps)
    }

    public var vpnIsActive: Bool {
        if defaultRoute?.isTunnel == true { return true }
        if campusRoute?.isTunnel == true { return true }
        return tunnels.contains { $0.isUp }
    }
}

/// 采集器：全是只读操作（`getifaddrs` / `SCDynamicStore` / `route get`）。
public struct NetworkInspector: Sendable {
    public init() {}

    public func snapshot(campusHost: IPv4Address = PacketLayout.defaultServer) -> NetworkSnapshot {
        let provider = SystemInterfaceProvider()
        let raw = SystemInterfaceProvider.allInterfaces()
        let defaultRoute = provider.route(to: IPv4Address("0.0.0.0")!)
        let campusRoute = provider.route(to: campusHost)

        let interfaces = raw
            .filter { !VirtualInterfaceNames.isVirtual($0.name) || isPhysicalEn($0.name) }
            .map { item in
                NetworkSnapshot.InterfaceRow(
                    name: item.name, index: item.index, ipv4: item.ipv4, mask: item.netmask,
                    mac: item.mac, linkLocal: item.linkLocalIPv4,
                    isWireless: item.isWireless, isUSB: item.isUSB, isUp: item.isUp,
                    isDefaultRoute: defaultRoute?.interface == item.name,
                    carriesCampusRoute: campusRoute?.interface == item.name,
                    hardwareName: item.hardwareName)
            }
            // 能用来认证、并且有地址的口排前面，方便用户一眼找到"该用哪个"
            .sorted { lhs, rhs in
                let leftScore = (lhs.ipv4 != nil ? 2 : 0) + (lhs.carriesCampusRoute ? 1 : 0)
                let rightScore = (rhs.ipv4 != nil ? 2 : 0) + (rhs.carriesCampusRoute ? 1 : 0)
                if leftScore != rightScore { return leftScore > rightScore }
                return lhs.name < rhs.name
            }

        let tunnels = raw
            .filter { VirtualInterfaceNames.isVirtual($0.name) && $0.name.hasPrefix("utun") }
            .map { NetworkSnapshot.TunnelRow(name: $0.name, ipv4: $0.ipv4, ipv6: nil, isUp: $0.isUp) }
            // 有地址（真正在承载流量）的隧道排前面
            .sorted { ($0.ipv4 != nil ? 1 : 0, $0.name) > ($1.ipv4 != nil ? 1 : 0, $1.name) }

        let dns = Self.systemDNS()
        return NetworkSnapshot(
            interfaces: interfaces, tunnels: tunnels,
            defaultRoute: defaultRoute, campusRoute: campusRoute,
            dnsServers: dns,
            dnsLooksHijacked: dns.contains { $0.hasPrefix("198.18.") })
    }

    private func isPhysicalEn(_ name: String) -> Bool { name.hasPrefix("en") }

    /// 读系统 DNS（只用于**展示**；探针仍然自己发 UDP 查询，不用系统解析器）。
    public static func systemDNS() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "dev.jlugate.dns" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString),
              let dictionary = value as? [String: Any],
              let servers = dictionary["ServerAddresses"] as? [String] else {
            return []
        }
        return servers
    }
}

// MARK: - Ping（TCP 握手 RTT，不需要 root）

public struct PingTarget: Sendable, Equatable, Identifiable {
    public var id: String { "\(label)-\(host)" }
    public let label: String
    public let host: IPv4Address
    public let port: UInt16

    public init(label: String, host: IPv4Address, port: UInt16) {
        self.label = label
        self.host = host
        self.port = port
    }

    public static func defaults(snapshot: NetworkSnapshot) -> [PingTarget] {
        var targets: [PingTarget] = []
        // 先测"离你最近的一跳"：默认路由的网关，没有就退回认证流量那条路由的网关
        let gateway = snapshot.defaultRoute?.gateway ?? snapshot.campusRoute?.gateway
        if let gateway, let ip = IPv4Address(gateway) {
            targets.append(PingTarget(label: "网关", host: ip, port: 80))
        }
        // 认证服务器本身只开 UDP 61440，用 TCP 去"ping"它必然不通，所以不列，避免误导
        // 公网用 80 端口：很多校园网只放行 80/443 的一部分，80 最能反映"到得了外面吗"
        targets.append(PingTarget(label: "公网（阿里 DNS）", host: IPv4Address("223.5.5.5")!, port: 80))
        targets.append(PingTarget(label: "公网（Cloudflare）", host: IPv4Address("1.1.1.1")!, port: 80))
        return targets
    }
}

public struct PingService: Sendable {
    public init() {}

    /// 同一条目标测两遍：绑物理口（直连）与走系统默认路由（含 VPN），用来看 VPN 的额外延迟。
    public func compare(_ target: PingTarget, interface: InterfaceSnapshot?,
                        attempts: Int = 4) async -> (direct: PingSummary, viaDefault: PingSummary) {
        let direct = await ping(target, interface: interface, attempts: attempts)
        let viaDefault = await ping(target, interface: nil, attempts: attempts)
        return (direct, viaDefault)
    }

    /// 用一个 TCP 握手量延迟：不需要 root，也不依赖 ICMP 被放行。
    /// `interface == nil` 表示走系统默认路由（也就是 VPN/TUN 那条路）。
    public func ping(_ target: PingTarget, interface: InterfaceSnapshot?,
                     attempts: Int = 4, timeout: Duration = .milliseconds(1200)) async -> PingSummary {
        var latencies: [Double] = []
        for _ in 0..<attempts {
            if let rtt = Self.tcpHandshake(host: target.host, port: target.port,
                                           interface: interface, timeout: timeout) {
                latencies.append(rtt)
            }
        }
        return PingSummary(host: "\(target.label) \(target.host)",
                           latencies: latencies, attempted: attempts)
    }

    static func tcpHandshake(host: IPv4Address, port: UInt16,
                             interface: InterfaceSnapshot?, timeout: Duration) -> Double? {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        if let interface {
            var index = interface.index
            guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index,
                             socklen_t(MemoryLayout<UInt32>.size)) == 0 else { return nil }
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: host.uint32BE.bigEndian)

        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let started = ContinuousClock.now
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0, errno != EINPROGRESS { return nil }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let milliseconds = Int32(max(1, timeout.components.seconds * 1000
            + timeout.components.attoseconds / 1_000_000_000_000_000))
        let ready = poll(&descriptor, 1, milliseconds)
        guard ready > 0 else { return nil }

        var soError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
        guard soError == 0 else { return nil }

        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }
}

// MARK: - 测速（HTTP 下载；直连 vs 走 VPN 对比）

public struct SpeedEndpoint: Sendable, Equatable {
    public let label: String
    public let host: String
    public let path: String

    public init(label: String, host: String, path: String) {
        self.label = label
        self.host = host
        self.path = path
    }

    /// 只用**纯 HTTP、且真的会吐大文件**的端点（我们不引 TLS 依赖）：
    /// CacheFly / ThinkBroadband 是经典的 HTTP 测速文件；
    /// 国内网络通常阿里云镜像更快，作为第三个候选。
    public static let defaults: [SpeedEndpoint] = [
        SpeedEndpoint(label: "清华镜像", host: "mirrors.tuna.tsinghua.edu.cn",
                      path: "/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso"),
        SpeedEndpoint(label: "中科大镜像", host: "mirrors.ustc.edu.cn",
                      path: "/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso"),
        SpeedEndpoint(label: "网易镜像", host: "mirrors.163.com",
                      path: "/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso"),
        SpeedEndpoint(label: "ThinkBroadband", host: "ipv4.download.thinkbroadband.com",
                      path: "/5MB.zip"),
    ]
}

public struct SpeedResult: Sendable, Equatable, Hashable {
    public let label: String
    public let endpoint: String
    public let boundInterface: String?
    public let bytes: Int
    public let seconds: Double

    public var megabitsPerSecond: Double {
        Throughput.megabitsPerSecond(bytes: bytes, seconds: seconds)
    }

    public var description: String {
        let via = boundInterface.map { "网口 \($0) 直连" } ?? "当前默认出口（含 VPN）"
        return "\(via)：\(Throughput.format(megabitsPerSecond: megabitsPerSecond))"
    }
}

public struct SpeedTestService: Sendable {
    public init() {}

    /// 下载 `maxBytes` 字节并计算速度。`interface == nil` = 走系统默认路由（VPN/TUN）。
    ///
    /// 优先用 `/usr/bin/curl` 量带宽：它能正确走 HTTPS、跟随跳转、处理拥塞窗口；
    /// 手写 recv 循环在这类测速上会低估一个数量级（实测 0.2 Mbps vs 真实 20 Mbps）。
    public func download(endpoint: SpeedEndpoint, interface: InterfaceSnapshot?,
                         maxBytes: Int = 3_000_000,
                         timeout: Duration = .seconds(10)) async -> SpeedResult? {
        // curl 失败（例如直连被网关限制）就如实返回 nil，让 UI 说"不可用"，
        // 不用手写 recv 循环兜底：实测它会低估一个数量级，反而误导用户。
        return Self.measureWithCurl(endpoint: endpoint, interface: interface,
                                    maxBytes: maxBytes, timeout: timeout)
    }

    static func measureWithCurl(endpoint: SpeedEndpoint, interface: InterfaceSnapshot?,
                                maxBytes: Int, timeout: Duration) -> SpeedResult? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else { return nil }
        let url = "http://\(endpoint.host)\(endpoint.path)"
        // 注意：不要加 --max-filesize——它会让 curl 直接拒绝下载（exit 63、size=0）。
        // 用 --max-time 限时，按"这段时间下载了多少字节"算速度。
        _ = maxBytes
        var arguments = ["-s", "-o", "/dev/null",
                         "--max-time", "\(timeout.components.seconds)",
                         "-w", "%{size_download} %{time_total}",
                         url]
        if let interface {
            arguments.insert(contentsOf: ["--interface", interface.name], at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let parts = output.split(separator: " ")
        guard parts.count == 2,
              let bytes = Double(parts[0]), let seconds = Double(parts[1]),
              bytes >= 64 * 1024, seconds > 0 else { return nil }
        return SpeedResult(label: endpoint.label,
                           endpoint: "\(endpoint.host)\(endpoint.path)",
                           boundInterface: interface?.name,
                           bytes: Int(bytes), seconds: seconds)
    }

    /// 没有 curl 时的兜底（纯 BSD socket，只支持 HTTP）。
    func downloadWithBSD(endpoint: SpeedEndpoint, interface: InterfaceSnapshot?,
                         maxBytes: Int, timeout: Duration) async -> SpeedResult? {
        let addresses = await Self.resolve(endpoint.host, interface: interface)
        guard let address = addresses.first else { return nil }
        let started = ContinuousClock.now
        let bytes = Self.httpDownload(ip: address, host: endpoint.host, path: endpoint.path,
                                      maxBytes: maxBytes, timeout: timeout)
        let elapsed = ContinuousClock.now - started
        // 太小（<64 KB）基本是错误页/重定向页，别当作测速结果
        guard bytes >= 64 * 1024 else { return nil }
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        return SpeedResult(label: endpoint.label,
                           endpoint: "\(endpoint.host)\(endpoint.path)",
                           boundInterface: interface?.name,
                           bytes: bytes, seconds: seconds)
    }

    /// 直连（绑物理口）与走 VPN（默认路由）各测一次，给出对比。
    public func compare(interface: InterfaceSnapshot?,
                        endpoints: [SpeedEndpoint] = SpeedEndpoint.defaults) async -> [SpeedResult] {
        var results: [SpeedResult] = []
        for endpoint in endpoints.prefix(2) {
            if let direct = await download(endpoint: endpoint, interface: interface) {
                results.append(direct)
            }
        }
        for endpoint in endpoints.prefix(2) {
            if let vpn = await download(endpoint: endpoint, interface: nil) {
                results.append(vpn)
            }
        }
        return results
    }

    // MARK: 内部

    /// 自己解析（优先公共 DNS），避免系统 DNS 被代理换成 fake-ip。
    static func resolve(_ host: String, interface: InterfaceSnapshot?) async -> [IPv4Address] {
        if let literal = IPv4Address(host) { return [literal] }
        var addresses: [IPv4Address] = []
        for server in ConnectivityProbe.fallbackDNSServers {
            if let found = try? await BSDProbeTransport().resolve(
                host: host, server: server,
                interface: interface ?? InterfaceSnapshot(name: "en0", index: 0, ipv4: nil, mac: nil,
                                                          isWireless: false, isUp: true),
                timeout: .seconds(2)), !found.isEmpty {
                addresses = found
                break
            }
        }
        return addresses
    }

    static func httpDownload(ip: IPv4Address, host: String, path: String,
                             maxBytes: Int, timeout: Duration, redirectsLeft: Int = 2) -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return 0 }
        defer { Darwin.close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(80).bigEndian
        address.sin_addr = in_addr(s_addr: ip.uint32BE.bigEndian)

        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { return 0 }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&descriptor, 1, 3000) > 0 else { return 0 }
            var soError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
            guard soError == 0 else { return 0 }
        }

        let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: JLUGate-Speedtest\r\n"
            + "Accept: */*\r\nConnection: close\r\n\r\n"
        let payload = Array(request.utf8)
        _ = payload.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var headerBytes: [UInt8] = []
        var headerDone = false
        var total = 0
        // 用单调时钟做截止：这台机器上 Date() 会被系统对时跳变，用它当 deadline 会永远跑不完
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 1500) > 0 else { break }
            let read = recv(fd, &buffer, buffer.count, 0)
            if read < 0 {
                // 非阻塞 socket：EAGAIN 不是结束，只是这一轮没数据
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                break
            }
            if read == 0 { break }   // 对端关闭
            var chunk = Array(buffer[0..<read])

            if !headerDone {
                headerBytes.append(contentsOf: chunk)
                guard headerBytes.count <= 32 * 1024 else { return 0 }
                guard let headerEnd = Self.headerEnd(in: headerBytes) else { continue }
                headerDone = true
                let header = String(decoding: headerBytes[0..<headerEnd], as: UTF8.self)
                if let redirect = Self.redirectTarget(header: header, host: host, redirectsLeft: redirectsLeft) {
                    return httpDownload(ip: redirect.ip, host: redirect.host, path: redirect.path,
                                        maxBytes: maxBytes, timeout: timeout,
                                        redirectsLeft: redirectsLeft - 1)
                }
                chunk = Array(headerBytes[headerEnd...])
                headerBytes = []
            }

            total += chunk.count
            if total >= maxBytes { break }
        }
        return headerDone ? min(total, maxBytes) : 0
    }

    /// 3xx + Location → 解析出下一跳（只支持字面 IP 或同域名的 http 地址）。
    static func redirectTarget(header: String, host: String,
                               redirectsLeft: Int) -> (ip: IPv4Address, host: String, path: String)? {
        guard redirectsLeft > 0 else { return nil }
        let lines = header.split(separator: "\r\n").map(String.init)
        guard let statusLine = lines.first else { return nil }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]), (300..<400).contains(code) else { return nil }
        guard let locationLine = lines.first(where: { $0.lowercased().hasPrefix("location:") }) else { return nil }
        let value = locationLine.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
        // 只接受 http:// 形式（我们只做纯 HTTP 测速）
        var rest = value
        if let schemeRange = rest.range(of: "://") {
            guard rest[..<schemeRange.lowerBound].lowercased() == "http" else { return nil }
            rest = String(rest[schemeRange.upperBound...])
        }
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        var newHost = String(rest[..<slash])
        let path = String(rest[slash...])
        if let colon = newHost.firstIndex(of: ":") { newHost = String(newHost[..<colon]) }
        guard let ip = IPv4Address(newHost) else { return nil }
        _ = host
        return (ip, newHost, path)
    }

    /// 找到 `\r\n\r\n` 之后的正文起点。
    static func headerEnd(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 0..<(bytes.count - 3) where bytes[index] == 0x0D && bytes[index + 1] == 0x0A
            && bytes[index + 2] == 0x0D && bytes[index + 3] == 0x0A {
            return index + 4
        }
        return nil
    }
}
