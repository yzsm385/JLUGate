import Foundation

/// 把网口翻译成"这是谁的、用来干什么的"。
///
/// 用户看到 `en2`、`anpi0`、`utun4`、`bridge0` 这种名字是懵的；
/// 这里按名字前缀 + 系统给的硬件端口名 + 是否无线/USB 给出通俗解释。
public enum InterfacePurpose: String, Sendable, CaseIterable, Equatable {
    case wifi
    case wiredEthernet
    case usbEthernet
    case thunderboltEthernet
    case bridge
    case loopback
    case tunnel
    case appleInternal
    case directLink          // AirDrop / AirPlay 的直连通道（awdl / llw）
    case hotspot
    case other
}

public struct InterfaceExplanation: Sendable, Equatable {
    public let purpose: InterfacePurpose
    /// 用途（短标题）
    public let title: String
    /// 谁持有 / 谁创建的
    public let owner: String
    /// 能不能用来做校园网认证
    public let usableForAuthentication: Bool
    /// 一句话补充
    public let note: String
}

public enum InterfaceNarrator {
    /// - Parameters:
    ///   - hardwareName: `SCNetworkInterfaceGetLocalizedDisplayName`，例如 "Wi-Fi"、"USB 10/100/1000 LAN"
    ///   - proxyApps: 检测到正在运行的代理软件（用于解释 utun 是谁建的）
    public static func explain(name: String,
                               hardwareName: String?,
                               isWireless: Bool,
                               isUSB: Bool,
                               ipv4: String?,
                               proxyApps: [String] = []) -> InterfaceExplanation {
        let lowerName = name.lowercased()
        let lowerHardware = (hardwareName ?? "").lowercased()

        // 1) 回环
        if lowerName.hasPrefix("lo") {
            return InterfaceExplanation(
                purpose: .loopback, title: "回环（本机自己）",
                owner: "系统内核", usableForAuthentication: false,
                note: "127.0.0.1 只在本机内部用，永远不会把包发到网线上。")
        }

        // 2) 隧道 / VPN
        if isTunnelName(lowerName) {
            let owner = proxyApps.isEmpty
                ? "由 VPN/代理软件创建（当前没检测到具体进程）"
                : "由 \(proxyApps.joined(separator: "、")) 创建"
            return InterfaceExplanation(
                purpose: .tunnel, title: "虚拟网卡（隧道）",
                owner: owner, usableForAuthentication: false,
                note: "代理把它当作出口；如果它抢到了校园网段，认证包就到不了学校网关。")
        }

        // 3) Apple 内部接口
        if lowerName.hasPrefix("anpi") || lowerName.hasPrefix("nan") || lowerName.hasPrefix("ap") {
            return InterfaceExplanation(
                purpose: .appleInternal, title: "Apple 内部接口",
                owner: "系统/芯片组（不是你能插拔的网卡）", usableForAuthentication: false,
                note: "用于系统内部通信（如 iPhone 互联），和上网无关。")
        }

        // 4) AirDrop / AirPlay 直连
        if lowerName.hasPrefix("awdl") || lowerName.hasPrefix("llw") {
            return InterfaceExplanation(
                purpose: .directLink, title: "AirDrop / AirPlay 直连通道",
                owner: "系统（无线直连，不是上网口）", usableForAuthentication: false,
                note: "只用来和附近 Apple 设备直连，不承载上网流量。")
        }

        // 5) Thunderbolt Bridge
        if lowerName.hasPrefix("bridge") || lowerHardware.contains("thunderbolt bridge") {
            return InterfaceExplanation(
                purpose: .bridge, title: "Thunderbolt 桥接",
                owner: "系统自动创建（两台 Mac 直连时用）", usableForAuthentication: false,
                note: "一般用不到；如果它被当成默认出口，说明网络配置乱了。")
        }

        // 6) Wi-Fi
        if isWireless || lowerHardware.contains("wi-fi") || lowerHardware.contains("airport") {
            return InterfaceExplanation(
                purpose: .wifi, title: "Wi-Fi（无线）",
                owner: "内置无线网卡（或有线转无线的适配器）", usableForAuthentication: true,
                note: "JLU.WIFI 走这个口做网页认证；JLU.PC 也用它跑 Dr.Com。")
        }

        // 7) USB 网卡
        if isUSB || lowerHardware.contains("usb") {
            return InterfaceExplanation(
                purpose: .usbEthernet, title: "USB 有线网卡",
                owner: "外接 USB 网卡（换 USB 口可能改名，靠 MAC 认它）", usableForAuthentication: true,
                note: ipv4 == nil
                    ? "当前没有 IPv4：多半是新插的网卡还没配静态地址。"
                    : "换口/换卡后接口名会变；学校登记的是 MAC，所以一定要核对 MAC。")
        }

        // 8) 雷雳/内置有线
        if lowerHardware.contains("thunderbolt") || lowerHardware.contains("ethernet") {
            let title = lowerHardware.contains("thunderbolt") ? "雷雳/Thunderbolt 网卡" : "内置/外接有线网卡"
            return InterfaceExplanation(
                purpose: lowerHardware.contains("thunderbolt") ? .thunderboltEthernet : .wiredEthernet,
                title: title,
                owner: lowerHardware.contains("thunderbolt")
                    ? "雷雳/Thunderbolt 扩展坞上的网口"
                    : "系统内置或扩展坞上的有线网口",
                usableForAuthentication: true,
                note: ipv4 == nil
                    ? "当前没有 IPv4：插好网线或给它配静态地址后才能认证。"
                    : "有线接入时用它：IP/掩码/网关必须与学校分配的一致。")
        }

        // 9) 其他 en*
        if lowerName.hasPrefix("en") {
            return InterfaceExplanation(
                purpose: .wiredEthernet, title: "有线网卡",
                owner: "系统网络接口", usableForAuthentication: true,
                note: ipv4 == nil ? "当前没有 IPv4：插好网线或给它配静态地址后才能认证。" : "可用于认证。")
        }

        return InterfaceExplanation(
            purpose: .other, title: "其他接口",
            owner: "系统", usableForAuthentication: false,
            note: "与上网无关，可忽略。")
    }

    static func isTunnelName(_ name: String) -> Bool {
        ["utun", "tun", "tap", "ppp", "ipsec"].contains { name.hasPrefix($0) }
    }
}
