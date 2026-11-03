import Foundation
import Darwin
import SystemConfiguration
import JLUGateCore

/// 从 `getifaddrs` 读物理口（无需权限），并调用 `route(8)` / `ipconfig(8)` 做只读诊断。
///
/// 铁律（CHECKLIST §7）：**一切按 MAC 认口，不按接口名**。USB 网卡换个口就变 en→enX。
public struct SystemInterfaceProvider: InterfaceProvider {
    public init() {}

    public func physicalInterfaces() -> [InterfaceSnapshot] {
        Self.allInterfaces()
            .filter { !VirtualInterfaceNames.isVirtual($0.name) && $0.isUp && !$0.isLoopback }
            .map { snapshot in
                guard snapshot.mac == nil || snapshot.mac == Self.placeholderMAC else { return snapshot }
                guard let mac = Self.ethernetAddress(from: "/sbin/ifconfig", interface: snapshot.name) else {
                    return snapshot
                }
                return InterfaceSnapshot(name: snapshot.name, index: snapshot.index,
                                         ipv4: snapshot.ipv4, mac: mac,
                                         isWireless: snapshot.isWireless, isUp: snapshot.isUp,
                                         isUSB: snapshot.isUSB,
                                         linkLocalIPv4: snapshot.linkLocalIPv4,
                                         netmask: snapshot.netmask)
            }
    }

    /// 某些环境（虚拟机 / 隐私模式）下 `getifaddrs` 的 AF_LINK 只给全零或 `02:00:00:…`，
    /// 而登录包里的 MAC 必须是**网卡当前真正使用的那个**（学校按 MAC 登记）。
    /// 所以这里回落到 `ifconfig` 的 `ether` 行（只读、无需 root）。
    static let placeholderMAC = "02:00:00:00:00:00"

    static func ethernetAddress(from tool: String, interface name: String) -> String? {
        let output = PortOccupancy.shell(tool, [name])
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ether ") else { continue }
            let value = trimmed.dropFirst("ether ".count).trimmingCharacters(in: .whitespaces)
            if MACAddress(value) != nil { return value }
        }
        return nil
    }

    public func snapshot(of name: String) -> InterfaceSnapshot? {
        Self.allInterfaces().first { $0.name == name }
    }

    public func route(to host: IPv4Address) -> RouteInfo? {
        let output = PortOccupancy.shell("/sbin/route", ["-n", "get", host.description])
        guard !output.isEmpty else { return nil }
        var gateway: String?
        var interface: String?
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "gateway": gateway = value
            case "interface": interface = value
            default: break
            }
        }
        return RouteInfo(destination: host.description, gateway: gateway, interface: interface)
    }

    public func configMethod(of name: String) -> String? {
        let output = PortOccupancy.shell("/usr/sbin/ipconfig", ["getsummary", name])
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("configmethod") else { continue }
            let value = trimmed.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            return value.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public func defaultGateway() -> String? {
        let output = PortOccupancy.shell("/sbin/route", ["-n", "get", "default"])
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("gateway:") {
                return trimmed.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: getifaddrs

    static func allInterfaces() -> [InterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        struct Acc {
            var ipv4: String?
            var mac: String?
            var linkLocal: String?
            var netmask: String?
            var isUp = false
            var index: UInt32 = 0
            var isWireless = false
        }
        let hardwareTable = Self.hardwareInfo()
        var table: [String: Acc] = [:]
        var order: [String] = []

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let pointer = entry.pointee
            let name = Self.decode(pointer.ifa_name)
            if table[name] == nil {
                table[name] = Acc()
                order.append(name)
            }
            var acc = table[name]!
            acc.isUp = (pointer.ifa_flags & UInt32(IFF_UP)) != 0
            acc.index = if_nametoindex(pointer.ifa_name)
            acc.isWireless = hardwareTable[name]?.isWireless ?? false

            if let address = pointer.ifa_addr {
                let family = address.pointee.sa_family
                if family == sa_family_t(AF_INET) {
                    let addressText = Self.text(address)
                    if addressText.hasPrefix("169.254.") {
                        acc.linkLocal = addressText
                    } else if acc.ipv4 == nil {
                        acc.ipv4 = addressText
                    }
                    if let mask = pointer.ifa_netmask, acc.netmask == nil {
                        acc.netmask = Self.text(mask)
                    }
                } else if family == sa_family_t(AF_LINK) {
                    let link = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self)
                    // MAC 在 `sdl_data + sdl_nlen` 处；必须按 address 结构自身的长度算，别越界读。
                    if link.pointee.sdl_alen == 6 {
                        let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8
                        let total = Int(link.pointee.sdl_len)
                        let macStart = dataOffset + Int(link.pointee.sdl_nlen)
                        if total >= macStart + 6 {
                            let raw = UnsafeRawBufferPointer(
                                start: UnsafeRawPointer(link).advanced(by: macStart), count: 6)
                            acc.mac = MACAddress(bytes: Array(raw))?.description
                        }
                    }
                }
            }
            table[name] = acc
            cursor = pointer.ifa_next
        }

        return order.compactMap { name -> InterfaceSnapshot? in
            guard let acc = table[name] else { return nil }
            return InterfaceSnapshot(
                name: name,
                index: acc.index,
                ipv4: acc.ipv4,
                mac: acc.mac,
                isWireless: acc.isWireless,
                isUp: acc.isUp,
                isUSB: hardwareTable[name]?.isUSB ?? false,
                linkLocalIPv4: acc.linkLocal,
                netmask: acc.netmask)
        }
    }

    /// 网卡类型判定：用 **SystemConfiguration**（纯 API，不起子进程）。
    ///
    /// 之前用 `networksetup` 子进程 + `static let` 缓存，会在 `dispatch_once` 初始化期间
    /// 阻塞等待进程，被另一线程重入后触发
    /// `BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively` —— 直接崩 app。
    struct HardwareInfo: Sendable {
        var isWireless = false
        var isUSB = false
    }

    static func hardwareInfo() -> [String: HardwareInfo] {
        var table: [String: HardwareInfo] = [:]
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return table
        }
        for interface in interfaces {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
            let displayName = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? ""
            var info = HardwareInfo()
            info.isWireless = (type == (kSCNetworkInterfaceTypeIEEE80211 as String))
            info.isUSB = type == (kSCNetworkInterfaceTypeEthernet as String)
                && displayName.lowercased().contains("usb")
            table[name] = info
        }
        return table
    }

    /// `String(cString:)` 在当前 SDK 已废弃，这里统一走 NUL 截断 + UTF8 解码。
    private static func decode(_ pointer: UnsafePointer<CChar>) -> String {
        let length = strlen(pointer)
        return String(decoding: UnsafeBufferPointer(start: pointer, count: length).map { UInt8(bitPattern: $0) },
                      as: UTF8.self)
    }

    private static func text(_ pointer: UnsafePointer<sockaddr>) -> String {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(pointer.pointee.sa_len)
        guard getnameinfo(pointer, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return ""
        }
        return Self.decode(host)
    }
}
