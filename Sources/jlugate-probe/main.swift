import Foundation
import Darwin
import JLUGateCore
import JLUGateNet

/// `jlugate-probe`：M0/M3 的离线与真机探针。
///
/// - `--self-test`：对着 `127.0.0.1` 的模拟网关跑完整流程（**施工机唯一能做的联网动作**）。
/// - `--interfaces` / `--route-check`：只读诊断，不改任何系统状态。
/// - `--dump-login`：离线打印 342 字节登录包（人工核对偏移用）。
/// - `--login`：**真机**认证（只能在环境 B 上跑；本机没有 Dr.Com 环境）。

struct Options {
    var command = "help"
    var account = ""
    var password = ""
    var hostname = ""
    var mac: String?
    var server = PacketLayout.defaultServer.description
    var serverPort = Int(PacketLayout.serverPort)
    var localPort = Int(PacketLayout.localPort)
    var keepAliveSeconds = 10.0
    var keepAliveExplicit = false
    var seconds = 8.0
    var salt = "49cb720f"
    /// `--frame <path>`：用来解析一个已抓到的登录帧
    var framePath: String?
    /// `--ip`：dump-login 时用的客户端 IP
    var ip = "192.0.2.10"
    /// `--proxy host:port`：带宽测试里"套了一层住宅代理"那一档
    var proxy: String?
    /// `--variant legacy|current`：选择登录报文版本
    var variant = "current"
    /// `--link-local 169.254.x.y`：登录包里的第二 IP
    var linkLocal: String?
    /// `--nonce2 aabb`：覆盖尾部随机字节（调试/黄金复现）
    var nonce2: String?
    var gatewayPort = 61441
    var gatewayPath = "Tools/mock-gateway/mock_gateway.py"
    var portalPort = 18080
    var dnsServers: [String] = []
    var portalPath = "Tools/mock-portal/portal_server.py"
    /// `--portal-entry <url>`：静默登录测试用的门户入口
    var portalEntry = "http://net.jlu.edu.cn/"
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    options.hostname = defaultHostname()
    var index = 1
    if arguments.count > 1, !arguments[1].hasPrefix("--") {
        options.command = arguments[1]
        index = 2
    }
    while index < arguments.count {
        let key = arguments[index]
        func value() -> String {
            index += 1
            return index < arguments.count ? arguments[index] : ""
        }
        switch key {
        case "--account": options.account = value()
        case "--password": options.password = value()
        case "--hostname": options.hostname = value()
        case "--mac": options.mac = value()
        case "--server": options.server = value()
        case "--server-port": options.serverPort = Int(value()) ?? options.serverPort
        case "--local-port": options.localPort = Int(value()) ?? options.localPort
        case "--keepalive":
            options.keepAliveSeconds = Double(value()) ?? options.keepAliveSeconds
            options.keepAliveExplicit = true
        case "--seconds": options.seconds = Double(value()) ?? options.seconds
        case "--salt": options.salt = value()
        case "--frame": options.framePath = value()
        case "--ip": options.ip = value()
        case "--proxy": options.proxy = value()
        case "--variant": options.variant = value()
        case "--link-local": options.linkLocal = value()
        case "--nonce2": options.nonce2 = value()
        case "--gateway-port": options.gatewayPort = Int(value()) ?? options.gatewayPort
        case "--portal-port": options.portalPort = Int(value()) ?? options.portalPort
        case "--portal-entry": options.portalEntry = value()
        case "--dns": options.dnsServers = value().split(separator: ",").map(String.init)
        default:
            if key.hasPrefix("--") { options.command = String(key.dropFirst(2)) }
        }
        index += 1
    }
    return options
}

/// 主机名最多 26 字节（`PacketLayout.Login.hostnameLength`），超了必须截断。
func defaultHostname() -> String {
    let raw = ProcessInfo.processInfo.hostName
    var text = raw
    if !text.lowercased().hasSuffix(".local") { text += ".local" }
    while text.utf8.count > PacketLayout.Login.hostnameLength { text.removeLast() }
    return text
}

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func hexBytes(_ text: String) -> [UInt8] {
    var result: [UInt8] = []
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
        if let value = UInt8(text[index..<next], radix: 16) { result.append(value) }
        index = next
    }
    return result
}

func printHelp() {
    print("""
    jlugate-probe — JLU Gate 诊断与离线自测

    用法：
      jlugate-probe --self-test [--seconds 8] [--keepalive 1]   # 对 127.0.0.1 模拟网关跑全流程
      jlugate-probe --portal-self-test [--seconds 8]            # 对 127.0.0.1 模拟门户跑网页认证
      jlugate-probe --interfaces                                # 列出物理网卡（只读）
      jlugate-probe --route-check [--server 10.100.61.3]        # 路由出口 / ConfigMethod（只读）
      jlugate-probe --detect                                    # 判定当前网络走哪条链路（会发 1 个 challenge）
      jlugate-probe --portal-check                              # 只看网页认证链路的在线判定（不发任何认证）
      jlugate-probe --net-detail                                # 网口/路由/DNS/VPN 全量快照（比终端清楚）
      jlugate-probe --ping                                      # TCP 握手延迟（网关/认证服务器/公网）
      jlugate-probe --speed                                     # 下载测速：网口直连 vs 当前出口（含 VPN）
      jlugate-probe --auth-ping                                 # 认证通道往返延迟：直连 vs 经代理
      jlugate-probe --mac-check                                 # 三处 MAC 对照（排查"匹配不上"）
      jlugate-probe --inspect                                   # 网络体检：出口 IP / WebRTC / DNS / 人机验证
      jlugate-probe --reach                                     # 能不能上网：逐站点分层排查 + 结论
      jlugate-probe --reputation                                # 出口 IP 纯净度（住宅 or 机房）
      jlugate-probe --speed3 [--proxy 127.0.0.1:7890]           # 带宽三档：直连 / 默认出口 / 本地代理
      jlugate-probe --frame <hex文件>                            # 解析一个登录帧（和 --dump-login 对照）
      jlugate-probe --dump-login --account X --password Y       # 离线打印 342 字节登录包
      jlugate-probe --login --account X --password Y [--mac ..] # 真机认证（只能在环境 B 执行）

    铁律：施工机不做任何真实认证（CHECKLIST §0 / PLAN §14）。
    """)
}

// MARK: - 命令

func runInterfaces() {
    let provider = SystemInterfaceProvider()
    let all = provider.physicalInterfaces()
    if all.isEmpty {
        print("没有可用的物理接口（或全部已 down）")
        return
    }
    print("name  ifindex  ipv4             mac                wireless  linkLocal         mask")
    for item in all {
        print(String(format: "%-5@ %-7u %-16@ %-18@ %-8@ %-16@ %@",
                     item.name as NSString, item.index,
                     (item.ipv4 ?? "-") as NSString,
                     (item.mac ?? "-") as NSString,
                     (item.isWireless ? "yes" : "no") as NSString,
                     (item.linkLocalIPv4 ?? "-") as NSString,
                     (item.netmask ?? "-") as NSString))
    }
}

func runRouteCheck(_ options: Options) {
    let provider = SystemInterfaceProvider()
    guard let host = IPv4Address(options.server) else {
        print("服务器地址不合法：\(options.server)")
        return
    }
    print("目标: \(host):\(options.serverPort)")
    if let route = provider.route(to: host) {
        print("路由出口: \(route.interface ?? "?")   网关: \(route.gateway ?? "-")")
        if route.isTunnel {
            print("⚠️ 出口是虚拟接口（\(route.interface ?? "?")）：认证包会被代理吞掉。")
            print("   请在代理规则里把 10.0.0.0/8 设为 DIRECT，或给该物理口加一条 -ifscope 的 /32 路由。")
        } else {
            print("✅ 出口是物理接口，报文不会进 TUN")
        }
    } else {
        print("⚠️ 拿不到 \(options.server) 的路由（route get 失败）")
    }
    for item in provider.physicalInterfaces() {
        let method = provider.configMethod(of: item.name) ?? "未知"
        print("接口 \(item.name)  ConfigMethod=\(method)\(method.lowercased() == "manual" ? "" : "  ⚠️ 必须是 Manual")")
    }
    if let gateway = provider.defaultGateway() {
        print("默认网关: \(gateway)")
    }
}

func runDumpLogin(_ options: Options) {
    guard !options.account.isEmpty, !options.password.isEmpty else {
        print("需要 --account 与 --password")
        return
    }
    guard let ip = IPv4Address(options.ip), let mac = MACAddress(options.mac ?? "02:00:00:00:00:01") else {
        print("IP/MAC 参数不合法")
        return
    }
    let context = LoginContext(
        account: options.account,
        password: options.password,
        salt: hexBytes(options.salt),
        clientIP: ip,
        linkLocalIP: options.linkLocal.flatMap(IPv4Address.init),
        hostname: options.hostname,
        mac: mac,
        nonceOverrides: NonceOverrides(nonce2: options.nonce2.flatMap(hexBytes)))
    do {
        let variant: LoginVariant = options.variant == "legacy" ? .legacy : .current
        let frame = try DrcomCodec().makeLogin(context, variant: variant)
        print("长度: \(frame.count)")
        for offset in stride(from: 0, to: frame.count, by: 16) {
            let chunk = [UInt8](frame[offset..<min(offset + 16, frame.count)])
            let ascii = String(decoding: chunk.map { (32...126).contains($0) ? $0 : 0x2E }, as: UTF8.self)
            print(String(format: "%04x  %-47@ %@", offset, hexString(chunk) as NSString, ascii as NSString))
        }
        print("HEX:" + frame.map { String(format: "%02x", $0) }.joined())
        let digest = DrcomCodec.digestA(password: options.password, salt: hexBytes(options.salt))
        print("摘要 A: \(hexString(digest))")
    } catch {
        print("编码失败：\(error)")
    }
}

// MARK: - 链路判定（真机）

/// 只做判定、**不认证**：对候选口各发 1 个 challenge（3s 超时、不重试），再跑 204 探针。
/// 结果就是 `AuthCoordinator` 在 `auto` 下会做的选择。
func runDetect(_ options: Options) -> Int32 {
    print("⚠️ 该命令会向 \(options.server):\(options.serverPort) 各发 1 个 challenge（不认证），只应在环境 B 上跑。")
    let provider = SystemInterfaceProvider()
    let detector = DefaultLinkDetector()
    let server = IPv4Endpoint(host: IPv4Address(options.server) ?? PacketLayout.defaultServer,
                              port: UInt16(options.serverPort))

    let candidates = provider.physicalInterfaces()
    guard !candidates.isEmpty else {
        print("没有物理接口")
        return 2
    }
    print("候选接口：\(candidates.map(\.name).joined(separator: ", "))")

    let semaphore = DispatchSemaphore(value: 0)
    let verdict = ResultBox2()
    Task.detached {
        for item in candidates {
            let reachable = await detector.probeDrcom(interface: item, server: server,
                                                      localPort: UInt16(options.localPort),
                                                      timeout: .seconds(3))
            print("  \(item.name)（\(item.ipv4 ?? "无 IPv4")）Dr.Com challenge：\(reachable ? "有回执 ✅" : "无回执")")
            if reachable {
                verdict.link = item.isWireless ? .jluPC : .wired
                semaphore.signal()
                return
            }
        }
        let dns: [IPv4Address] = options.dnsServers.compactMap(IPv4Address.init)
        let outcome = await detector.probeConnectivity(
            interface: candidates.first(where: { $0.ipv4 != nil }) ?? candidates[0],
            dnsServers: dns.isEmpty ? ConnectivityProbe.fallbackDNSServers : dns)
        switch outcome {
        case .healthy:
            print("  204 探针：已在线（无需认证）")
            verdict.alreadyOnline = true
        case .captivePortal(let code, let location):
            print("  204 探针：被拦截（HTTP \(code) \(location ?? "")）→ 应走 JLU.WIFI 网页认证")
            verdict.link = .jluWiFi
        case .unreachable(let reason):
            print("  204 探针：不通（\(reason)）")
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)

    if verdict.alreadyOnline {
        print("结论：当前已在线上，不需要认证。")
    } else if let link = verdict.link {
        print("结论：应走【\(link.displayName)】。")
    } else {
        print("结论：当前网络不是校园网（两个探针都不通）。")
    }
    return 0
}

final class ResultBox2: @unchecked Sendable {
    var link: AccessLink?
    var alreadyOnline = false
}

// MARK: - 网络详情（只读）

func runNetDetail(_ options: Options) -> Int32 {
    let snapshot = NetworkInspector().snapshot()

    print("== 网口 ==")
    for row in snapshot.interfaces {
        var marks: [String] = []
        if row.isDefaultRoute { marks.append("默认出口") }
        if row.carriesCampusRoute { marks.append("承载认证流量") }
        if row.isWireless { marks.append("无线") }
        if row.isUSB { marks.append("USB") }
        if !row.isUp { marks.append("down") }
        let markText = marks.isEmpty ? "" : "  [\(marks.joined(separator: "、"))]"
        let macText = row.mac ?? "-"
        let hardwareText = row.hardwareMAC.map { "（出厂 \($0)）" } ?? ""
        print("\(row.name) ifindex=\(row.index)  ipv4=\(row.ipv4 ?? "-")/\(row.mask ?? "-")  mac=\(macText)\(hardwareText)\(markText)")
        let info = InterfaceNarrator.explain(name: row.name, hardwareName: row.hardwareName,
                                             isWireless: row.isWireless, isUSB: row.isUSB,
                                             ipv4: row.ipv4)
        print("   用途：\(info.title)｜持有者：\(info.owner)")
        print("   \(info.note)")
    }

    print("\n== 隧道 / VPN ==")
    if snapshot.tunnels.isEmpty {
        print("没有 utun 接口，VPN/TUN 未开启")
    } else {
        for tunnel in snapshot.tunnels {
            print("\(tunnel.name)  ipv4=\(tunnel.ipv4 ?? "-")  \(tunnel.isUp ? "up" : "down")")
        }
    }
    print("默认出口：\(snapshot.defaultRoute?.interface ?? "-")（网关 \(snapshot.defaultRoute?.gateway ?? "-")）")
    print("10.100.61.3 出口：\(snapshot.campusRoute?.interface ?? "-")")
    print("VPN/TUN 是否在生效：\(snapshot.vpnIsActive ? "是" : "否")")

    let analysis = ProxyModeAnalyzer.analyze(snapshot.proxyFacts())
    print("\n== 代理模式 ==")
    print("\(analysis.mode.title)")
    print(analysis.summary)
    print("建议：\(analysis.advice)")

    print("\n== DNS ==")
    print(snapshot.dnsServers.isEmpty ? "（读不到）" : snapshot.dnsServers.joined(separator: ", "))
    if snapshot.dnsLooksHijacked {
        print("⚠️ 出现 198.18.x.x：DNS 被代理劫持成 fake-ip")
    }

    print("\n== 字段说明 ==")
    for entry in FieldGuide.entries {
        print("· \(entry.term)：\(entry.explanation)")
    }
    return 0
}

func runPingCheck(_ options: Options) -> Int32 {
    let snapshot = NetworkInspector().snapshot()
    guard let interface = SystemInterfaceProvider().physicalInterfaces()
        .first(where: { $0.isUsableForAuthentication }) else {
        print("没有可用网口")
        return 2
    }
    print("通过 \(interface.name)（\(interface.ipv4 ?? "-")）探测 TCP 握手延迟：")
    let service = PingService()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        for target in PingTarget.defaults(snapshot: snapshot) {
            let pair = await service.compare(target, interface: interface)
            print("  " + pair.direct.description)
            print("    经默认出口：\(pair.viaDefault.description)")
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 40)
    return 0
}

func runSpeedCheck(_ options: Options) -> Int32 {
    guard let interface = SystemInterfaceProvider().physicalInterfaces()
        .first(where: { $0.isUsableForAuthentication }) else {
        print("没有可用网口")
        return 2
    }
    print("测速：先绑 \(interface.name) 直连，再走默认出口（含 VPN）。最多 6 MB / 端点。")
    let service = SpeedTestService()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let results = await service.compare(interface: interface)
        if results.isEmpty {
            print("❌ 测速失败（端点不可达；可换 --speed-url 指定 HTTP 测速地址）")
        }
        for result in results {
            print("  " + result.description
                  + String(format: "  [%d 字节 / %.2f 秒, %@]", result.bytes, result.seconds, result.endpoint))
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 90)
    return 0
}

func runAuthPing(_ options: Options) -> Int32 {
    guard let interface = SystemInterfaceProvider().physicalInterfaces()
        .first(where: { $0.isUsableForAuthentication }) else {
        print("没有可用网口")
        return 2
    }
    print("发真实 challenge 测认证通道（\(interface.name) 直连 vs 默认出口）：")
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let sample = await AuthLivenessProbe().measure(interface: interface)
        print("  " + sample.direct.description)
        print("  " + sample.viaDefault.description)
        print("  结论：" + sample.verdict)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)
    return 0
}

// MARK: - 网页认证链路在线判定（真机，只读）

/// 不弹窗的浏览器替身：本命令只验证"探针/在线判定"，不涉及登录。
final class SilentPortalBrowser: PortalBrowser, @unchecked Sendable {
    func presentLogin(url: URL) async -> PortalLoginResult {
        print("  需要人工登录：\(url.absoluteString)")
        return .cancelled
    }
    func clearCookies() async {}
}

func runPortalCheck(_ options: Options) -> Int32 {
    let provider = SystemInterfaceProvider()
    guard let interface = provider.physicalInterfaces().first(where: { $0.isUsableForAuthentication }) else {
        print("没有可用于认证的物理接口（有线/Wi-Fi 都要有 IPv4）")
        return 2
    }
    let dns: [IPv4Address] = options.dnsServers.compactMap(IPv4Address.init)
    let dnsServers = dns.isEmpty ? ConnectivityProbe.fallbackDNSServers : dns
    print("接口：\(interface.name)（\(interface.ipv4 ?? "-")）  DNS：\(dnsServers.map(\.description))")

    let configuration = PortalConfiguration(
        silentRetryOnce: true,
        silentRetryDelay: .milliseconds(300),
        promptCooldown: .seconds(300),
        probeInterval: .seconds(3),
        failTolerance: 2,
        dnsServers: dnsServers,
        successChecks: 2)
    let engine = PortalEngine(probe: ConnectivityProbe(),
                              browser: SilentPortalBrowser(),
                              detector: PortalDetector(),
                              configuration: configuration)
    // 调试用：有账号密码就试一次后台静默登录（不弹网页）
    if !options.account.isEmpty, !options.password.isEmpty {
        let account = options.account
        let password = options.password
        let credentials = PortalCredentials(account: account, password: password,
                                            clientMAC: interface.mac)
        Task { await engine.setCredentials(credentials) }
        print("静默登录：已注入账号 \(account)（密码不打印）")
    }

    let semaphore = DispatchSemaphore(value: 0)
    let box = PortalStateBox()
    Task.detached {
        let stream = await engine.events()
        let collector = Task {
            for await event in stream {
                switch event {
                case .state(let state):
                    box.states.append(state.phase)
                    print("状态 → \(state.phase)")
                case .entry(let url): print("入口 → \(url.absoluteString)")
                case .note(let message): print("日志：\(message)")
                case .online: box.online = true
                case .needsUser: print("需要人工登录")
                }
            }
        }
        await engine.start(using: interface)
        try? await Task.sleep(for: .seconds(8))
        await engine.stop()
        collector.cancel()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 20)

    if box.online || box.states.contains("online") {
        print("✅ 当前链路已在线（204 通过），不需要网页登录")
        return 0
    }
    if box.states.contains("authenticating") {
        print("⚠️ 当前链路需要网页登录（App 里点「登录」会弹 WKWebView）")
        return 0
    }
    print("❌ 在线判定失败；状态序列：\(box.states.joined(separator: " → "))")
    return 1
}

// MARK: - 自测（对模拟网关）

struct LoopbackProvider: InterfaceProvider {
    let interface: InterfaceSnapshot

    func physicalInterfaces() -> [InterfaceSnapshot] { [interface] }
    func snapshot(of name: String) -> InterfaceSnapshot? { interface.name == name ? interface : nil }
    func route(to host: IPv4Address) -> RouteInfo? {
        RouteInfo(destination: host.description, gateway: nil, interface: interface.name)
    }
    func configMethod(of name: String) -> String? { "Manual" }
    func defaultGateway() -> String? { nil }
}

final class ResultBox: @unchecked Sendable {
    var sawOnline = false
    var keepAliveReplies = 0
    var states: [String] = []
}

func runSelfTest(_ options: Options) -> Int32 {
    guard FileManager.default.fileExists(atPath: options.gatewayPath) else {
        print("找不到模拟网关：\(options.gatewayPath)（请在仓库根目录执行）")
        return 2
    }

    let account = options.account.isEmpty ? "20230001" : options.account
    let password = options.password.isEmpty ? "test-pass-2024" : options.password

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "python3", options.gatewayPath,
        "--host", "127.0.0.1",
        "--port", String(options.gatewayPort),
        "--duration", String(options.seconds + 4),
        "--assert",
        "--account", account,
        "--password", password,
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        print("启动模拟网关失败：\(error)")
        return 2
    }
    // 给网关一点启动时间
    Thread.sleep(forTimeInterval: 0.3)

    guard let loopbackIndex = UInt32(exactly: if_nametoindex("lo0")) else {
        print("拿不到 lo0 的 ifindex")
        process.terminate()
        return 2
    }
    let snapshot = InterfaceSnapshot(
        name: "lo0", index: loopbackIndex, ipv4: "127.0.0.1", mac: nil,
        isWireless: false, isUp: true, isUSB: false, linkLocalIPv4: nil, netmask: "255.0.0.0")

    // 离线自测为了几秒内看到至少一轮保活，默认把间隔压到 1s（真机仍用配置里的 10s）
    let keepAlive = options.keepAliveExplicit ? options.keepAliveSeconds : 1.0
    let configuration = EngineConfiguration(
        account: account, password: password, hostname: options.hostname,
        registeredMAC: nil, interfaceLock: "lo0",
        server: IPv4Address("127.0.0.1")!,
        serverPort: UInt16(options.gatewayPort),
        localPort: UInt16(options.localPort),
        keepAliveInterval: .seconds(keepAlive),
        missTolerance: 3)

    let engine = DrcomEngine(
        configuration: configuration,
        codec: DrcomCodec(),
        channelFactory: BSDChannelFactory(),
        interfaces: LoopbackProvider(interface: snapshot),
        clock: SystemClock())

    let semaphore = DispatchSemaphore(value: 0)
    let result = ResultBox()

    Task.detached {
        let stream = await engine.events()
        let collector = Task {
            for await event in stream {
                switch event {
                case .state(let state):
                    result.states.append(state.phase)
                    print("状态 → \(state.phase)")
                case .traffic(let seconds, let stats):
                    result.keepAliveReplies += 1
                    print("保活应答：在线 \(seconds)s 统计 \(stats)")
                case .session(let account, let clientIP, let session):
                    print("会话建立：\(account) @ \(clientIP ?? "-") session=\(String(format: "0x%04x", session))")
                case .log(let message):
                    print("日志：\(message)")
                }
            }
        }
        await engine.start()
        try? await Task.sleep(for: .seconds(options.seconds))
        await engine.stop()
        collector.cancel()
        result.sawOnline = result.states.contains("online")
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + options.seconds + 15)

    // 让网关自己跑完 --duration（自测时长 + 4s），这样才能拿到它的断言结论
    let exitDeadline = Date().addingTimeInterval(6)
    while process.isRunning && Date() < exitDeadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
    if process.isRunning { process.terminate() }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let gatewayLog = String(decoding: output, as: UTF8.self)

    print("—— 模拟网关输出 ——")
    print(gatewayLog.isEmpty ? "(空)" : gatewayLog)
    print("—— 自测结果 ——")
    print("状态序列：\(result.states.joined(separator: " → "))")
    print("保活应答次数：\(result.keepAliveReplies)")

    let gatewayOK = process.terminationStatus == 0 || gatewayLog.contains("OK packets=")
    let clientOK = result.sawOnline && result.keepAliveReplies >= 1
    if gatewayOK && clientOK {
        print("✅ 自测通过（编码器 + 通道 + 状态机 + 保活）")
        return 0
    }
    print("❌ 自测失败：gatewayOK=\(gatewayOK) online=\(result.sawOnline) keepAlive=\(result.keepAliveReplies)")
    return 1
}


// MARK: - 网页认证自测（对模拟门户）

/// 不跟随跳转的 delegate：这样才能看见真实的 302 与 Location。
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// 把"204 探针"换成本地 HTTP 站点：语义与 `ConnectivityProbe` 完全一样。
struct LocalPortalProbe: ConnectivityProbing {
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

/// 自测用的"浏览器"：取页面 → 找 form action → POST 表单。
///
/// ⚠️ 这是**测试替身**，只存在于 `jlugate-probe` 的离线自测里，不参与任何生产路径。
/// 生产实现是 `WKWebView`（`App/Sources/WKPortalBrowser.swift`），按决策 D-001
/// **不做表单自动化、不预填、不接触明文密码**。
final class CLIPortalBrowser: PortalBrowser, @unchecked Sendable {
    let account: String
    let password: String
    private let fetcher = URLSessionPortalFetcher()

    init(account: String, password: String) {
        self.account = account
        self.password = password
    }

    func presentLogin(url: URL) async -> PortalLoginResult {
        var target = url
        let dummy = InterfaceSnapshot(name: "lo0", index: 1, ipv4: "127.0.0.1", mac: nil,
                                      isWireless: false, isUp: true)
        if let page = try? await fetcher.fetch(url, interface: dummy),
           let action = PortalDetector.formAction(in: page.body, base: url) {
            target = action
            print("  登录页表单 action → \(action.absoluteString)")
        }
        print("  POST \(target.absoluteString)（账号 \(account)）")

        let body = "username=\(percentEncode(account))&password=\(percentEncode(password))"
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            let text = String(decoding: data, as: UTF8.self)
            guard let http = response as? HTTPURLResponse else {
                return .failed(reason: "没有 HTTP 响应")
            }
            if text.contains("错误") || text.contains("error") {
                return .failed(reason: text)
            }
            guard (200..<400).contains(http.statusCode) else {
                return .failed(reason: "HTTP \(http.statusCode)")
            }
            return .succeeded
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    func clearCookies() async {}

    private func percentEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}

func runPortalSelfTest(_ options: Options) -> Int32 {
    guard FileManager.default.fileExists(atPath: options.portalPath) else {
        print("找不到模拟门户：\(options.portalPath)（请在仓库根目录执行）")
        return 2
    }
    let account = options.account.isEmpty ? "20230001" : options.account
    let password = options.password.isEmpty ? "test-pass-2024" : options.password

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", options.portalPath,
                         "--host", "127.0.0.1", "--port", String(options.portalPort),
                         "--user", account, "--password", password]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        print("启动模拟门户失败：\(error)")
        return 2
    }
    Thread.sleep(forTimeInterval: 0.4)
    defer { if process.isRunning { process.terminate() } }

    guard let base = URL(string: "http://127.0.0.1:\(options.portalPort)") else {
        print("门户地址不合法")
        return 2
    }
    let interface = InterfaceSnapshot(name: "lo0", index: 1, ipv4: "127.0.0.1", mac: nil,
                                      isWireless: true, isUp: true, linkLocalIPv4: nil,
                                      netmask: "255.0.0.0")
    let configuration = PortalConfiguration(
        silentRetryOnce: true,
        silentRetryDelay: .milliseconds(300),
        promptCooldown: .seconds(300),
        probeInterval: .seconds(1),
        failTolerance: 2,
        successChecks: 5)
    let engine = PortalEngine(
        probe: LocalPortalProbe(base: base),
        browser: CLIPortalBrowser(account: account, password: password),
        detector: PortalDetector(configuredURL: base.appendingPathComponent("portal")),
        configuration: configuration)

    let semaphore = DispatchSemaphore(value: 0)
    let recorder = PortalStateBox()
    Task.detached {
        let stream = await engine.events()
        let collector = Task {
            for await event in stream {
                switch event {
                case .state(let state):
                    recorder.states.append(state.phase)
                    print("状态 → \(state.phase)")
                case .entry(let url):
                    print("门户入口 → \(url.absoluteString)")
                case .note(let message): print("日志：\(message)")
                case .online: print("已在线（204 通过）")
                case .needsUser: print("需要用户登录")
                }
            }
        }
        await engine.start(using: interface)
        try? await Task.sleep(for: .seconds(options.seconds))
        await engine.stop()
        collector.cancel()
        recorder.online = recorder.states.contains("online")
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + options.seconds + 15)

    if process.isRunning { process.terminate() }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let serverLog = String(decoding: output, as: UTF8.self)

    print("—— 模拟门户输出 ——")
    print(serverLog.isEmpty ? "(空)" : serverLog)
    print("—— 自测结果 ——")
    print("状态序列：\(recorder.states.joined(separator: " → "))")
    if recorder.online {
        print("✅ 网页认证自测通过（302 → 登录页 → POST → 204）")
        return 0
    }
    print("❌ 网页认证自测失败")
    return 1
}

final class PortalStateBox: @unchecked Sendable {
    var states: [String] = []
    var online = false
}

// MARK: - 真机认证

func runLogin(_ options: Options) -> Int32 {
    guard !options.account.isEmpty, !options.password.isEmpty else {
        print("需要 --account 与 --password")
        return 2
    }
    guard let server = IPv4Address(options.server) else {
        print("服务器地址不合法")
        return 2
    }
    print("⚠️ 只允许在环境 B（有线 Mac）执行本命令；施工机不做任何真实认证。")
    print("目标网关 \(server):\(options.serverPort)，本地端口 \(options.localPort)（必须固定）")

    let provider = SystemInterfaceProvider()
    if let route = provider.route(to: server), route.isTunnel {
        print("❌ 出口是 \(route.interface ?? "?")（代理 TUN）。先放行 10.0.0.0/8 再试。")
        return 3
    }

    let configuration = EngineConfiguration(
        account: options.account,
        password: options.password,
        hostname: options.hostname,
        registeredMAC: options.mac.flatMap(MACAddress.init),
        server: server,
        serverPort: UInt16(options.serverPort),
        localPort: UInt16(options.localPort),
        keepAliveInterval: .seconds(options.keepAliveSeconds))

    let engine = DrcomEngine(
        configuration: configuration,
        channelFactory: NWChannelFactory(),
        interfaces: provider)

    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let stream = await engine.events()
        let collector = Task {
            for await event in stream {
                switch event {
                case .state(let state): print("状态 → \(state.phase)")
                case .traffic(let seconds, _): print("在线 \(seconds)s")
                case .session(let account, let clientIP, _): print("会话：\(account) @ \(clientIP ?? "-")")
                case .log(let message): print("日志：\(message)")
                }
            }
        }
        await engine.start()
        try? await Task.sleep(for: .seconds(options.seconds))
        let finalState = await engine.currentState()
        let session = await engine.currentSession()
        await engine.stop()
        collector.cancel()
        if case .failed(let error) = finalState {
            print("失败：\(error.userMessage)")
        }
        if let ticket = session.ticket {
            print("会话号 \(String(format: "0x%04x", ticket.session))，客户端 IP \(ticket.clientIP)")
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + options.seconds + 15)
    return 0
}

// MARK: - 入口

let options = parseOptions(CommandLine.arguments)
switch options.command {
case "self-test":
    exit(runSelfTest(options))
case "portal-self-test":
    exit(runPortalSelfTest(options))
case "interfaces":
    runInterfaces()
case "route-check":
    runRouteCheck(options)
case "detect":
    exit(runDetect(options))
case "portal-check":
    exit(runPortalCheck(options))
case "eportal-login":
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        _ = await EportalProbeCLI.run(entry: options.portalEntry,
                                      account: options.account, password: options.password)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)
    exit(0)
case "net-detail":
    exit(runNetDetail(options))
case "ping":
    exit(runPingCheck(options))
case "speed":
    exit(runSpeedCheck(options))
case "auth-ping":
    exit(runAuthPing(options))
case "mac-check":
    exit(runMACCheck())
case "frame":
    exit(runFrameDump(options))
case "inspect":
    exit(runInspect())
case "reach":
    exit(runReach())
case "reputation":
    exit(runReputation())
case "speed3":
    exit(runSpeed3(options))
case "dump-login":
    runDumpLogin(options)
case "login":
    exit(runLogin(options))
default:
    printHelp()
}

/// 解析一个 342 字节登录帧，按我们的布局把关键字段打出来。
/// 用途：把官方客户端抓到的登录帧喂进来，和我们的 `--dump-login` 对照，看差在哪个字段。
func runFrameDump(_ options: Options) -> Int32 {
    guard let path = options.framePath,
          let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("用法：--frame <十六进制文本文件>（一行，342 字节）")
        return 2
    }
    let hex = text.filter(\.isHexDigit)
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        if let byte = UInt8(hex[index..<next], radix: 16) { bytes.append(byte) }
        index = next
    }
    guard bytes.count >= 60 else {
        print("字节数太少：\(bytes.count)")
        return 2
    }
    print("帧长：\(bytes.count) 字节（登录帧应为 342）")
    print("类型：\(Hex.string(bytes, limit: 2))  版本：\(Hex.string(Array(bytes[2..<4])))")
    print("0x00..0x10：\(Hex.string(bytes, limit: 16))")
    let mac = Array(bytes.count >= 0x152 ? bytes[0x14C..<0x152] : [])
    print("0x14C MAC：\(MACAddress(bytes: mac)?.description ?? Hex.string(mac))")
    if bytes.count >= 0x1E5 {
        let ip = Array(bytes[0x1E1..<0x1E5])
        print("0x1E1 IP：\(ip.map(String.init).joined(separator: "."))")
    }
    // 主机名：从 0x270 起按   截断
    if bytes.count > 0x270 {
        var name: [UInt8] = []
        for byte in bytes[0x270...] where byte != 0 { name.append(byte) }
        print("0x270 主机名：\(String(decoding: name, as: UTF8.self))")
    }
    if bytes.count >= 0x294 {
        print("0x294 归属字段：\(Hex.string(Array(bytes[0x290..<0x29C])))")
    }
    print("00 0c 标记（0x143/0x144）：\(Hex.string(Array(bytes[0x142..<0x146])))")
    print("末尾 8 字节：\(Hex.string(Array(bytes[(bytes.count - 8)...])))")
    return 0
}


/// 能不能上网：逐站点、逐层排查（DNS / TCP / TLS / HTTP）
func runReach() -> Int32 {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let results = await ReachabilityService().checkAll()
        for result in results where !result.isCampus {
            print(String(format: "  %-18@ %-8@ %@",
                         result.host as NSString,
                         (result.milliseconds.map { "\($0) ms" } ?? "-") as NSString,
                         result.display as NSString))
        }
        if results.contains(where: \.isCampus) {
            print("  校内系统：")
            for result in results where result.isCampus {
                print(String(format: "  %-18@ %-8@ %@",
                             result.host as NSString,
                             (result.milliseconds.map { "\($0) ms" } ?? "-") as NSString,
                             result.display as NSString))
            }
        }
        let provider = SystemInterfaceProvider()
        let interface = provider.physicalInterfaces().first { $0.isUsableForAuthentication }
        let route = interface.flatMap { _ in provider.route(to: PacketLayout.defaultServer) }
        let diagnosis = ReachabilityDiagnosisEngine.diagnose(
            sites: results,
            campusAuthReachable: nil,   // 只有 Dr.Com 链路才需要校内认证服务器，这里不测
            hasUsableInterface: interface != nil,
            proxyInUse: route?.isTunnel ?? false)
        print("")
        print("结论：\(diagnosis.summary)")
        print("建议：\(diagnosis.action)")
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 60)
    return 0
}

/// IP 纯净度：住宅还是机房、有没有被标记代理
func runReputation() -> Int32 {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let trace = await InspectionService().cloudflareTrace()
        guard let ip = trace?.ip else {
            print("拿不到出口 IP")
            semaphore.signal()
            return
        }
        let service = IPReputationService()
        let consensus = await service.geoConsensus(ip: ip)
        print("== 多源归属 ==")
        for sample in consensus.samples {
            print("  \(sample.source): \(sample.short)")
        }
        if consensus.countryDisagreement {
            print("  ⚠️ 多源国家不一致：\(consensus.countries.joined(separator: " / "))")
        }
        if let reputation = await service.lookup(ip: ip, cloudflareCountry: trace?.location) {
            print("  结论：" + reputation.summary)
            for note in reputation.notes { print("  · " + note) }
        }

        // DNS 出口 vs IP 出口
        let dns = await InspectionService().dnsLeak()
        var dnsCountry: String?
        if let egress = dns.systemEgress {
            dnsCountry = await service.geoConsensus(ip: egress).country
        }
        let alignment = DNSIPAlignmentEngine.align(ip: ip, ipCountry: consensus.country,
                                                   dnsEgress: dns.systemEgress,
                                                   dnsCountry: dnsCountry)
        print("== DNS 与 IP 出口 ==")
        print("  " + alignment.explanation)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)
    return 0
}

/// 带宽三档：直连 / 默认出口 / 指定本地代理
func runSpeed3(_ options: Options) -> Int32 {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let provider = SystemInterfaceProvider()
        let interface = provider.physicalInterfaces().first { $0.isUsableForAuthentication }
        let endpoint = SpeedEndpoint.defaults[0]
        let service = SpeedTestService()
        let interfaceName = interface?.name ?? "-"
        if let direct = await service.download(endpoint: endpoint, interface: interface) {
            print("  直连（\(interfaceName)）：\(Throughput.format(megabitsPerSecond: direct.megabitsPerSecond))")
        } else {
            print("  直连：不可用")
        }
        if let viaDefault = await service.download(endpoint: endpoint, interface: nil) {
            print("  默认出口（含代理）：\(Throughput.format(megabitsPerSecond: viaDefault.megabitsPerSecond))")
        } else {
            print("  默认出口：不可用")
        }
        let proxy = options.proxy ?? LocalProxyDetector.detect()?.hostPort
        if let proxy, !proxy.isEmpty {
            print("  使用代理：\(proxy)")
            if let viaProxy = await service.download(endpoint: endpoint, interface: nil, proxy: proxy) {
                print("  本地代理 \(proxy)：\(Throughput.format(megabitsPerSecond: viaProxy.megabitsPerSecond))")
            } else {
                print("  本地代理 \(proxy)：不可用")
            }
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 120)
    return 0
}

/// 网络体检：出口 IP / Cloudflare / WebRTC(STUN) / DNS 泄漏 / 人机验证可达性
func runInspect() -> Int32 {
    let service = InspectionService()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        print("== 出口 IP ==")
        let ips = await service.publicIPs()
        for sample in ips { print("  \(sample.source): \(sample.ip)") }
        if ips.isEmpty { print("  （一个都没拿到：可能整条出网被拦）") }

        print("\n== Cloudflare ==")
        if let trace = await service.cloudflareTrace() {
            print("  " + (trace.summary ?? "-"))
            print("  TLS \(trace.tls ?? "-") · HTTP \(trace.http ?? "-") · WARP \(trace.warp ?? "-")")
        } else {
            print("  trace 不可用")
        }

        print("\n== WebRTC（STUN）==")
        let rtc = await service.webRTC()
        print("  \(rtc.server) → \(rtc.publicIP ?? "无回执") \(rtc.port.map { ":\($0)" } ?? "")"
              + (rtc.latencyMilliseconds.map { "（\($0) ms）" } ?? ""))
        print("  " + InspectionVerdict.webRTCHint(rtc, localIP: nil))

        print("\n== DNS ==")
        let dns = await service.dnsLeak()
        print("  系统 DNS：\(dns.systemResolver ?? "-") → 出口 \(dns.systemEgress ?? "-")")
        print("  8.8.8.8 → 出口 \(dns.publicEgress ?? "-")")
        print("  疑似劫持：\(dns.hijackSuspected ? "是" : "否")")
        print("  " + dns.summary)

        print("\n== 人机验证 ==")
        let checks = await service.captchaChecks()
        for check in checks {
            print("  \(check.name)：\(check.human)"
                  + (check.latencyMilliseconds.map { "（\($0) ms）" } ?? "")
                  + (check.detail.map { " \($0)" } ?? ""))
        }
        print("  " + InspectionVerdict.captchaHint(checks))
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 60)
    return 0
}

/// 把"三处 MAC"一次打全，用于排查"为什么匹配不上"：
/// 每块网卡的 当前 MAC（getifaddrs）、出厂 MAC（SystemConfiguration）、出厂 MAC（networksetup）。
func runMACCheck() -> Int32 {
    let provider = SystemInterfaceProvider()
    print("== 登记值（配置里的 registeredMAC）==")
    print("  见 App 设置；命令行下从参数卡或设置里查看")
    print("")
    print("== 所有网卡 ==")
    print("name   ipv4            当前MAC(getifaddrs)     出厂MAC(SC)           出厂MAC(networksetup)")
    for item in SystemInterfaceProvider.allInterfaces() {
        let sc = item.hardwareMAC ?? "—"
        let ns = SystemInterfaceProvider.hardwareMAC(for: item.name) ?? "—"
        let ip = (item.ipv4 ?? "—").padding(toLength: 16, withPad: " ", startingAt: 0)
        print(String(format: "%-5@  %@  %-22@  %-20@  %@",
                     item.name as NSString, ip as NSString,
                     (item.mac ?? "—") as NSString, sc as NSString, ns as NSString))
    }
    print("")
    print("提示：第一位是 02/06/0a/0e/f2 等（U/L 位=1）就是系统套的私有 MAC；")
    print("      学校登记/官方客户端用的是「出厂」那一列。")
    return 0
}
