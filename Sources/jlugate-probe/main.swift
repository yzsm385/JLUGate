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
    var gatewayPort = 61441
    var gatewayPath = "Tools/mock-gateway/mock_gateway.py"
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
        case "--gateway-port": options.gatewayPort = Int(value()) ?? options.gatewayPort
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
      jlugate-probe --interfaces                                # 列出物理网卡（只读）
      jlugate-probe --route-check [--server 10.100.61.3]        # 路由出口 / ConfigMethod（只读）
      jlugate-probe --detect                                    # 判定当前网络走哪条链路（会发 1 个 challenge）
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
    guard let ip = IPv4Address("192.0.2.10"), let mac = MACAddress(options.mac ?? "02:00:00:00:00:01") else {
        print("IP/MAC 参数不合法")
        return
    }
    let context = LoginContext(
        account: options.account,
        password: options.password,
        salt: hexBytes(options.salt),
        clientIP: ip,
        linkLocalIP: IPv4Address("169.254.1.1"),
        hostname: options.hostname,
        mac: mac)
    do {
        let frame = try DrcomCodec().makeLogin(context)
        print("长度: \(frame.count)")
        for offset in stride(from: 0, to: frame.count, by: 16) {
            let chunk = [UInt8](frame[offset..<min(offset + 16, frame.count)])
            let ascii = String(decoding: chunk.map { (32...126).contains($0) ? $0 : 0x2E }, as: UTF8.self)
            print(String(format: "%04x  %-47@ %@", offset, hexString(chunk) as NSString, ascii as NSString))
        }
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
        let outcome = await detector.probeConnectivity(interface: candidates[0],
                                                       dnsServers: [IPv4Address("10.10.10.10")!])
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
case "interfaces":
    runInterfaces()
case "route-check":
    runRouteCheck(options)
case "detect":
    exit(runDetect(options))
case "dump-login":
    runDumpLogin(options)
case "login":
    exit(runLogin(options))
default:
    printHelp()
}
