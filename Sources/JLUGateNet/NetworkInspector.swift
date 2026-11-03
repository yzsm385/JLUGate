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
                    carriesCampusRoute: campusRoute?.interface == item.name)
            }

        let tunnels = raw
            .filter { VirtualInterfaceNames.isVirtual($0.name) && $0.name.hasPrefix("utun") }
            .map { NetworkSnapshot.TunnelRow(name: $0.name, ipv4: $0.ipv4, ipv6: nil, isUp: $0.isUp) }

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

    /// 默认用 Cloudflare 的测速端点；国内网络若不通会自动尝试第二个。
    public static let defaults: [SpeedEndpoint] = [
        SpeedEndpoint(label: "Cloudflare", host: "speed.cloudflare.com",
                      path: "/__down?bytes=10000000"),
        SpeedEndpoint(label: "CacheFly", host: "cachefly.cachefly.net", path: "/10mb.test"),
    ]
}

public struct SpeedResult: Sendable, Equatable {
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
    public func download(endpoint: SpeedEndpoint, interface: InterfaceSnapshot?,
                         maxBytes: Int = 6_000_000,
                         timeout: Duration = .seconds(15)) async -> SpeedResult? {
        let addresses = await Self.resolve(endpoint.host, interface: interface)
        guard let address = addresses.first else { return nil }
        let started = ContinuousClock.now
        let bytes = Self.httpDownload(ip: address, host: endpoint.host, path: endpoint.path,
                                      maxBytes: maxBytes, timeout: timeout)
        let elapsed = ContinuousClock.now - started
        guard bytes > 0 else { return nil }
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
        for endpoint in endpoints {
            if let direct = await download(endpoint: endpoint, interface: interface) {
                results.append(direct)
            }
        }
        for endpoint in endpoints {
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
                             maxBytes: Int, timeout: Duration) -> Int {
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

        let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: JLUGate\r\nConnection: close\r\n\r\n"
        let payload = Array(request.utf8)
        _ = payload.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total = 0
        var headerDone = false
        let deadline = Date().addingTimeInterval(Double(timeout.components.seconds))
        while total < maxBytes, Date() < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 1500) > 0 else { break }
            let read = recv(fd, &buffer, buffer.count, 0)
            guard read > 0 else { break }
            let chunk = Array(buffer[0..<read])
            if !headerDone {
                // 跳过 HTTP 头，只统计正文
                if let range = Self.headerEnd(in: chunk) {
                    headerDone = true
                    total += chunk.count - range
                }
                continue
            }
            total += chunk.count
        }
        return headerDone ? total : 0
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
