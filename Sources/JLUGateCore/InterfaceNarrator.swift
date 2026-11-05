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
                purpose: .loopback, title: Copy.t("B122"),
                owner: Copy.t("B123"), usableForAuthentication: false,
                note: Copy.t("B124"))
        }

        // 2) 隧道 / VPN
        if isTunnelName(lowerName) {
            let owner = proxyApps.isEmpty
                ? Copy.t("B125")
                : Copy.f("B126", proxyApps.joined(separator: "、"))
            return InterfaceExplanation(
                purpose: .tunnel, title: Copy.t("B127"),
                owner: owner, usableForAuthentication: false,
                note: Copy.t("B128"))
        }

        // 3) Apple 内部接口
        if lowerName.hasPrefix("anpi") || lowerName.hasPrefix("nan") || lowerName.hasPrefix("ap") {
            return InterfaceExplanation(
                purpose: .appleInternal, title: Copy.t("B129"),
                owner: Copy.t("B130"), usableForAuthentication: false,
                note: Copy.t("B131"))
        }

        // 4) AirDrop / AirPlay 直连
        if lowerName.hasPrefix("awdl") || lowerName.hasPrefix("llw") {
            return InterfaceExplanation(
                purpose: .directLink, title: Copy.t("B132"),
                owner: Copy.t("B133"), usableForAuthentication: false,
                note: Copy.t("B134"))
        }

        // 5) Thunderbolt Bridge
        if lowerName.hasPrefix("bridge") || lowerHardware.contains("thunderbolt bridge") {
            return InterfaceExplanation(
                purpose: .bridge, title: Copy.t("B135"),
                owner: Copy.t("B136"), usableForAuthentication: false,
                note: Copy.t("B137"))
        }

        // 6) Wi-Fi
        if isWireless || lowerHardware.contains("wi-fi") || lowerHardware.contains("airport") {
            return InterfaceExplanation(
                purpose: .wifi, title: Copy.t("B138"),
                owner: Copy.t("B139"), usableForAuthentication: true,
                note: Copy.t("B140"))
        }

        // 7) USB 网卡
        if isUSB || lowerHardware.contains("usb") {
            return InterfaceExplanation(
                purpose: .usbEthernet, title: Copy.t("B141"),
                owner: Copy.t("B142"), usableForAuthentication: true,
                note: ipv4 == nil
                    ? "当前没有 IPv4：多半是新插的网卡还没配静态地址。"
                    : Copy.t("B144"))
        }

        // 8) 雷雳/内置有线
        if lowerHardware.contains("thunderbolt") || lowerHardware.contains("ethernet") {
            let title = lowerHardware.contains("thunderbolt") ? Copy.t("B145") : Copy.t("B146")
            return InterfaceExplanation(
                purpose: lowerHardware.contains("thunderbolt") ? .thunderboltEthernet : .wiredEthernet,
                title: title,
                owner: lowerHardware.contains("thunderbolt")
                    ? Copy.t("B147")
                    : Copy.t("B148"),
                usableForAuthentication: true,
                note: ipv4 == nil
                    ? Copy.t("B149")
                    : Copy.t("B150"))
        }

        // 9) 其他 en*
        if lowerName.hasPrefix("en") {
            return InterfaceExplanation(
                purpose: .wiredEthernet, title: Copy.t("B151"),
                owner: Copy.t("B152"), usableForAuthentication: true,
                note: ipv4 == nil ? "当前没有 IPv4：插好网线或给它配静态地址后才能认证。" : Copy.t("B153"))
        }

        return InterfaceExplanation(
            purpose: .other, title: Copy.t("B154"),
            owner: Copy.t("B155"), usableForAuthentication: false,
            note: Copy.t("B156"))
    }

    static func isTunnelName(_ name: String) -> Bool {
        ["utun", "tun", "tap", "ppp", "ipsec"].contains { name.hasPrefix($0) }
    }
}
