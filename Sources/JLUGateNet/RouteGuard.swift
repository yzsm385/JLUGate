import Foundation
import JLUGateCore

/// 路由保障的三层结论（PLAN §6.5.1）。三层用**同一个** `route get` 判定，不许各写一套。
public enum RouteGuarantee: Sendable, Equatable {
    /// A 层：`route get` 的出口已经是物理口，零特权直接用。
    case direct(interface: String)
    /// B 层：出口是 utun，但 helper 已授权 → 让它加一条 `-ifscope` 的 /32。
    case helper(interface: String, host: String, gateway: String)
    /// C 层：只能给用户一条能复制的命令。
    case manual(command: String, interface: String)
    /// 连路由都拿不到（接口没起来 / 没有到该主机的路由）。
    case noRoute

    /// 是否可以继续认证（A、B 之后可以；C 要先让用户执行）。
    public var allowsAuthentication: Bool {
        switch self {
        case .direct, .helper: true
        case .manual, .noRoute: false
        }
    }
}

/// 纯粹的路由判定逻辑（不执行任何命令，全部可单测）。
public struct RouteGuard: Sendable {
    /// 允许 helper 操作的 /32 白名单。默认就是认证服务器。
    public var allowedHosts: Set<String>
    /// 用户档案里录入的网关（**不是**路由表里的、更不是写死的）。
    public var registeredGateway: String?

    public init(allowedHosts: Set<String> = [PacketLayout.defaultServer.description],
                registeredGateway: String? = nil) {
        self.allowedHosts = allowedHosts
        self.registeredGateway = registeredGateway
    }

    public func evaluate(route: RouteInfo?,
                         interface: InterfaceSnapshot,
                         helperAuthorized: Bool) -> RouteGuarantee {
        guard let route, let exit = route.interface else { return .noRoute }

        // A 层：出口本来就是物理口
        if !VirtualInterfaceNames.isVirtual(exit) {
            return .direct(interface: exit)
        }

        // B/C 层：出口被 TUN 接管。命令里的网关优先用档案里的，其次才是路由表里的。
        guard let gateway = registeredGateway ?? route.gateway,
              IPv4Address(gateway) != nil else {
            return .manual(command: Self.interfaceMissingGatewayHint(interface: interface.name),
                           interface: interface.name)
        }
        guard Self.isPhysicalInterfaceName(interface.name) else {
            return .manual(command: "（找不到物理网卡，无法给出路由命令）", interface: interface.name)
        }
        if helperAuthorized {
            return .helper(interface: interface.name,
                           host: allowedHosts.sorted().first ?? PacketLayout.defaultServer.description,
                           gateway: gateway)
        }
        return .manual(command: Self.manualAddCommand(host: allowedHosts.sorted().first
                                                      ?? PacketLayout.defaultServer.description,
                                                      gateway: gateway, interface: interface.name),
                       interface: interface.name)
    }

    /// C 层给用户复制的命令：只影响**绑定到该网卡**的 socket，不改系统默认路由。
    public static func manualAddCommand(host: String, gateway: String, interface name: String) -> String {
        "sudo route add -host \(host) -ifscope \(name) \(gateway)"
    }

    public static func manualRemoveCommand(host: String, interface name: String) -> String {
        "sudo route delete -host \(host) -ifscope \(name)"
    }

    static func interfaceMissingGatewayHint(interface: String) -> String {
        "（拿不到 \(interface) 的网关：请在设置里填写静态网关后再试）"
    }

    /// 物理口名只认 `en0`…（`utun`/`ppp`/`bridge` 一律拒绝）。
    public static func isPhysicalInterfaceName(_ name: String) -> Bool {
        guard name.hasPrefix("en"), name.count > 2 else { return false }
        return name.dropFirst(2).allSatisfy { $0.isNumber }
    }
}

// MARK: - helper 的入参校验（PLAN §6.6）

/// helper 只认这三个字段，别的什么都不接受。
public struct RouteRequest: Sendable, Equatable, Codable {
    public var host: String
    public var gateway: String
    public var interface: String

    public init(host: String, gateway: String, interface: String) {
        self.host = host
        self.gateway = gateway
        self.interface = interface
    }
}

public enum RouteRequestError: Error, Sendable, Equatable {
    case hostNotAllowed(String)
    case gatewayNotIPv4(String)
    case interfaceNotPhysical(String)
    case gatewayMismatch(expected: String?, actual: String)

    public var message: String {
        switch self {
        case .hostNotAllowed(let host):
            "拒绝：\(host) 不在 /32 白名单内"
        case .gatewayNotIPv4(let gateway):
            "拒绝：\(gateway) 不是 IPv4 字面量"
        case .interfaceNotPhysical(let name):
            "拒绝：\(name) 不是物理网卡（只允许 enN）"
        case .gatewayMismatch(let expected, let actual):
            "拒绝：网关 \(actual) 与该接口当前网关 \(expected ?? "未知") 不一致"
        }
    }
}

/// 参数白名单：**不拼 shell 字符串**，只产出 `route(8)` 的 argv 数组。
public struct RouteValidator: Sendable {
    public var allowedHosts: Set<String>

    public init(allowedHosts: Set<String> = [PacketLayout.defaultServer.description]) {
        self.allowedHosts = allowedHosts
    }

    public func validate(_ request: RouteRequest, interfaceGateway: String?) throws {
        // ① host 必须是白名单里的 IPv4 字面量（等价于 /32）
        guard IPv4Address(request.host) != nil, allowedHosts.contains(request.host) else {
            throw RouteRequestError.hostNotAllowed(request.host)
        }
        // ② gateway 必须是 IPv4 字面量（顺带挡住 "192.0.2.1; rm -rf /" 这类注入）
        guard IPv4Address(request.gateway) != nil else {
            throw RouteRequestError.gatewayNotIPv4(request.gateway)
        }
        // ③ 接口必须是 enN，且不能是虚拟口
        guard RouteGuard.isPhysicalInterfaceName(request.interface),
              !VirtualInterfaceNames.isVirtual(request.interface) else {
            throw RouteRequestError.interfaceNotPhysical(request.interface)
        }
        // ④ 网关必须是该接口自己的网关（防止 helper 被拿去改别的路由）
        if let interfaceGateway, IPv4Address(interfaceGateway) != nil, interfaceGateway != request.gateway {
            throw RouteRequestError.gatewayMismatch(expected: interfaceGateway, actual: request.gateway)
        }
    }

    /// 生成 `route -n add -host … -ifscope … …` 的 argv（第一个元素是工具路径）。
    public static func addArguments(_ request: RouteRequest) -> [String] {
        ["-n", "add", "-host", request.host, "-ifscope", request.interface, request.gateway]
    }

    public static func removeArguments(host: String, interface name: String) -> [String] {
        ["-n", "delete", "-host", host, "-ifscope", name]
    }

    /// helper 实际执行时用的可执行文件（绝对路径，不接受 PATH 查找）。
    public static let routeToolPath = "/sbin/route"
}
