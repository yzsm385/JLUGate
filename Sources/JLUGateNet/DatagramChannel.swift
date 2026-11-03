import Foundation
import JLUGateCore

public struct IPv4Endpoint: Sendable, Hashable, CustomStringConvertible {
    public let host: IPv4Address
    public let port: UInt16

    public init(host: IPv4Address, port: UInt16) {
        self.host = host
        self.port = port
    }

    public var description: String {
        "\(host):\(port)"
    }
}

/// 统一的数据报通道（PLAN §6.1）。两套实现：BSD（验证/兜底）与 NW（生产）。
///
/// 契约：
/// - `open` 必须**绑定源 IP 与固定本地端口**（61440），并把出口钉在 `interfaceIndex`；
/// - `receive` 超时抛 `DrcomError.timeout`，不返回空数据；
/// - `close` 可重复调用，必须幂等。
public protocol DatagramChannel: Sendable {
    func open(localIP: IPv4Address, localPort: UInt16,
              remote: IPv4Endpoint, interfaceIndex: UInt32) async throws
    func send(_ datagram: Data) async throws
    func receive(timeout: Duration) async throws -> Data
    func close() async
}

public protocol ChannelFactory: Sendable {
    func makeChannel() -> any DatagramChannel
}

/// 可注入的时钟（测试里用假时间，避免真睡）。
public protocol Clock: Sendable {
    func now() -> ContinuousClock.Instant
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> ContinuousClock.Instant { ContinuousClock.now }
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// 物理网卡快照（PLAN §4 的签名即契约，后 4 个字段是本实现补充的）。
public struct InterfaceSnapshot: Sendable, Equatable {
    public let name: String
    public let index: UInt32
    public let ipv4: String?
    public let mac: String?
    public let isWireless: Bool
    public let isUp: Bool
    /// USB 网卡（拔插后会换接口名，所以一切按 MAC 认）。
    public let isUSB: Bool
    /// 链路本地地址（169.254/16），登录包 0x055 要填它。
    public let linkLocalIPv4: String?
    /// 子网掩码（诊断用）。
    public let netmask: String?

    public init(name: String, index: UInt32, ipv4: String?, mac: String?,
                isWireless: Bool, isUp: Bool, isUSB: Bool = false,
                linkLocalIPv4: String? = nil, netmask: String? = nil) {
        self.name = name
        self.index = index
        self.ipv4 = ipv4
        self.mac = mac
        self.isWireless = isWireless
        self.isUp = isUp
        self.isUSB = isUSB
        self.linkLocalIPv4 = linkLocalIPv4
        self.netmask = netmask
    }

    public var ipv4Address: IPv4Address? {
        ipv4.flatMap(IPv4Address.init)
    }

    public var macAddress: MACAddress? {
        mac.flatMap(MACAddress.init)
    }

    /// 回环（127/8）永远不能用来做校园网认证。
    public var isLoopback: Bool {
        ipv4?.hasPrefix("127.") == true
    }

    /// 可以用于认证的候选：有 IPv4、不是回环、不是虚拟口。
    public var isUsableForAuthentication: Bool {
        ipv4 != nil && !isLoopback && !VirtualInterfaceNames.isVirtual(name)
    }
}

public struct RouteInfo: Sendable, Equatable {
    public let destination: String
    public let gateway: String?
    public let interface: String?

    public init(destination: String, gateway: String?, interface: String?) {
        self.destination = destination
        self.gateway = gateway
        self.interface = interface
    }

    /// 出口是不是虚拟/隧道接口（`utun`、`tun`、`ppp`、`ipsec`）。
    ///
    /// `lo0` 不算隧道：它是回环，选了它的问题已经在"选口"阶段被排除（`isUsableForAuthentication`）。
    public var isTunnel: Bool {
        guard let interface, !interface.hasPrefix("lo") else { return false }
        return VirtualInterfaceNames.isVirtual(interface)
    }
}

public enum VirtualInterfaceNames {
    /// `lo`（回环）与 `anpi`（Apple 内部接口）必须排除：
    /// 它们不是无线、又有 IPv4，打分时会把真正的 Wi-Fi/有线挤掉。
    private static let prefixes = [
        "utun", "tun", "tap", "ppp", "ipsec", "gif", "stf", "bridge", "awdl", "llw", "ap",
        "lo", "anpi", "ipsec",
    ]

    public static func isVirtual(_ name: String) -> Bool {
        prefixes.contains { name.hasPrefix($0) }
    }
}

public protocol InterfaceProvider: Sendable {
    func physicalInterfaces() -> [InterfaceSnapshot]
    func snapshot(of name: String) -> InterfaceSnapshot?
    /// `route get <host>` 的结果（判定是否被 TUN 接管）。
    func route(to host: IPv4Address) -> RouteInfo?
    /// `ipconfig getsummary <if>` 里的 `ConfigMethod`（必须是 Manual）。
    func configMethod(of name: String) -> String?
    func defaultGateway() -> String?
}
