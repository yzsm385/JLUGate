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
        /// 网页认证自检：指向 `Tools/mock-portal` 的基地址（如 http://127.0.0.1:18080）
        var portal: String?
        /// `"scripted"` 时用脚本化浏览器代替 WKWebView（仅用于无人值守自检）
        var browser: String?
        /// 自检时自动打开「网络详情」窗口
        var openNetDetail: Bool?
        var openSettings: Bool?
        /// 自检：启动后模拟"选有线 + 填完数据 + 保存"，复现闪退
        var saveWired: Bool?
        /// 自检：把每个面板视图都实例化并强制布局一次
        var uiProbe: Bool?
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

    /// 网页认证自检的目标基地址。
    static var portalBase: URL? {
        guard isEnabled else { return nil }
        guard let raw = fileConfig?.portal ?? value("JLUGATE_DEV_PORTAL", argument: "--dev-portal") else {
            return nil
        }
        return URL(string: raw)
    }

    static var uiProbeOnLaunch: Bool {
        guard isEnabled else { return false }
        return fileConfig?.uiProbe ?? false
    }

    /// 自检时模拟一次"有线 + 保存"的完整流程。
    static var saveWiredOnLaunch: Bool {
        guard isEnabled else { return false }
        return fileConfig?.saveWired ?? false
    }

    /// 自检时自动打开设置窗口。
    static var openSettingsOnLaunch: Bool {
        guard isEnabled else { return false }
        return fileConfig?.openSettings ?? false
    }

    /// 自检时自动打开「网络详情」窗口。
    static var openNetworkDetailOnLaunch: Bool {
        guard isEnabled else { return false }
        return fileConfig?.openNetDetail ?? false
    }

    /// 自检是否用脚本化浏览器代替真实的 WKWebView 窗口。
    static var portalUsesScriptedBrowser: Bool {
        guard isEnabled else { return false }
        return fileConfig?.browser == "scripted"
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

/// 自检用的"探针"：把 204 判定指向本地模拟门户（语义与 `ConnectivityProbe` 一致）。
struct DevPortalProbe: ConnectivityProbing {
    let base: URL

    func run(interface: InterfaceSnapshot, dnsServers: [IPv4Address]) async -> ProbeOutcome {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration,
                                 delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: base.appendingPathComponent("generate_204"))
        request.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(reason: "没有 HTTP 响应")
            }
            if http.statusCode == 204 { return .healthy }
            return .captivePortal(statusCode: http.statusCode,
                                  location: http.value(forHTTPHeaderField: "Location"))
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }
    }
}

/// 自检用的脚本化浏览器：只在 dev 配置里显式指定 `"browser": "scripted"` 时启用。
///
/// 真实产品路径是 `WKPortalBrowser`（普通 WKWebView，不做任何 DOM 操作，D-001）；
/// 这个替身只是为了让"无人值守自检"能跑完整条链路。
final class DevScriptedBrowser: PortalBrowser, @unchecked Sendable {
    let account: String
    let password: String

    init(account: String, password: String) {
        self.account = account
        self.password = password
    }

    func presentLogin(url: URL) async -> PortalLoginResult {
        FileLogger.shared.log("dev scripted browser: \(url.absoluteString)")
        var target = url
        let dummy = InterfaceSnapshot(name: "lo0", index: 1, ipv4: "127.0.0.1", mac: nil,
                                      isWireless: true, isUp: true)
        if let page = try? await URLSessionPortalFetcher().fetch(url, interface: dummy),
           let action = PortalDetector.formAction(in: page.body, base: url) {
            target = action
        }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.httpBody = Data("username=\(account)&password=\(password)".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("错误") { return .failed(reason: text) }
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return .failed(reason: "HTTP 异常")
            }
            return .succeeded
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    func clearCookies() async {}
}

/// 不跟随跳转，才能看到真实的 302 与 Location。
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
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
