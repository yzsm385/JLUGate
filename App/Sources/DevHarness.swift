import Foundation
import JLUGateCore
import JLUGateNet

#if canImport(Darwin)
import Darwin
#endif

/// 开发期自检用的**运行时开关**（不改变任何默认行为）：
/// 只有在环境里显式设置 `JLUGATE_DEV=1` 时生效，用来在没有校园网的机器上
/// 把真实 App 二进制接到本仓库的模拟网关上跑一遍。
///
///     JLUGATE_DEV=1 JLUGATE_DEV_SERVER=127.0.0.1 JLUGATE_DEV_PORT=61441 \
///       "dist/JLU Gate.app/Contents/MacOS/JLUGate"
///
/// 目的是验证"App → 协调器 → 引擎 → 通道 → 状态/遥测 → 日志"整条链路，
/// **不是**给最终用户的功能开关。
enum DevOverrides {
    /// `Contents/Resources/dev-config.json`（由 `make-app-bundle.sh --dev` 写入）。
    /// 用文件而不是 `open --args`：实测 `open --args` 不会把参数交给 AppKit 应用。
    private struct FileConfig: Decodable {
        var server: String?
        var port: UInt16?
        var autostart: Bool?
    }

    private static let fileConfig: FileConfig? = {
        guard let url = Bundle.main.url(forResource: "dev-config", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FileConfig.self, from: data)
    }()

    // 既支持环境变量（终端直接跑二进制），也支持上面的配置文件。
    private static func value(_ key: String, argument: String) -> String? {
        if let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty { return raw }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: argument), index + 1 < args.count {
            return args[index + 1]
        }
        return nil
    }

    private static func flag(_ key: String, argument: String) -> Bool {
        if ProcessInfo.processInfo.environment[key] == "1" { return true }
        return ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var isEnabled: Bool {
        fileConfig != nil || flag("JLUGATE_DEV", argument: "--jlugate-dev")
    }

    static var server: IPv4Address? {
        guard isEnabled else { return nil }
        if let raw = fileConfig?.server { return IPv4Address(raw) }
        guard let raw = value("JLUGATE_DEV_SERVER", argument: "--dev-server") else { return nil }
        return IPv4Address(raw)
    }

    /// 自检时自动发起登录（省掉手点菜单）。
    static var autostart: Bool {
        guard isEnabled else { return false }
        if let flag = fileConfig?.autostart { return flag }
        return flag("JLUGATE_DEV_AUTOSTART", argument: "--dev-autostart")
    }

    static var port: UInt16? {
        guard isEnabled else { return nil }
        if let port = fileConfig?.port { return port }
        guard let raw = value("JLUGATE_DEV_PORT", argument: "--dev-port"),
              let value = UInt16(raw) else { return nil }
        return value
    }
}

/// `JLUGATE_DEV` 模式下把"选口"换成回环，绕开 DHCP/物理网卡的校验。
struct DevLoopbackProvider: InterfaceProvider {
    private var snapshot: InterfaceSnapshot {
        let index = if_nametoindex("lo0")
        return InterfaceSnapshot(name: "lo0", index: index, ipv4: "127.0.0.1", mac: nil,
                                 isWireless: false, isUp: true, isUSB: false,
                                 linkLocalIPv4: nil, netmask: "255.0.0.0")
    }

    func physicalInterfaces() -> [InterfaceSnapshot] { [snapshot] }
    func snapshot(of name: String) -> InterfaceSnapshot? { name == "lo0" ? snapshot : nil }
    func route(to host: IPv4Address) -> RouteInfo? {
        RouteInfo(destination: host.description, gateway: nil, interface: "lo0")
    }
    func configMethod(of name: String) -> String? { "Manual" }
    func defaultGateway() -> String? { nil }
}
