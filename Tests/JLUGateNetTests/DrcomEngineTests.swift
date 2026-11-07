import Foundation
import Testing
import JLUGateCore
@testable import JLUGateNet

@Suite("引擎状态机（假通道 + 假时钟）", .serialized)
struct DrcomEngineTests {

    private func makeConfiguration(keepAliveInterval: Duration = .seconds(10)) -> EngineConfiguration {
        EngineConfiguration(
            account: "20230001",
            password: "test-pass-2024",
            hostname: "test-mac.local",
            registeredMAC: MACAddress("02:00:00:00:00:01"),
            keepAliveInterval: keepAliveInterval)
    }

    /// 登录包长度随密码长度变化（338 + 额外段），不能写死 342。
    static func isLoginFrame(_ data: Data) -> Bool {
        data.count >= 300 && data.first == 0x03
    }

    private func makeEngine(configuration: EngineConfiguration,
                            provider: FakeInterfaceProvider = .wired,
                            responder: @escaping @Sendable (Data) -> [Data])
        -> (engine: DrcomEngine, channel: FakeChannel, factory: RecordingChannelFactory, clock: FakeClock) {
        let channel = FakeChannel(responder: responder)
        let factory = RecordingChannelFactory(channel: channel)
        let clock = FakeClock()
        let engine = DrcomEngine(configuration: configuration,
                                 codec: DrcomCodec(randomness: SeededRandomSource(seed: 7)),
                                 channelFactory: factory,
                                 interfaces: provider,
                                 clock: clock,
                                 backoff: Backoff())
        return (engine, channel, factory, clock)
    }

    /// 模拟一个"规矩"的网关：challenge→salt、login→成功、保活按型应答。
    private func wellBehavedResponder(loginReply: Data? = nil) -> @Sendable (Data) -> [Data] {
        let success = loginReply ?? RecordedGateway.loginSuccess()
        return { datagram in
            if Self.isLoginFrame(datagram) { return [success] }
            switch datagram.count {
            case 20: return [RecordedGateway.challengeReply()]
            case 38: return [RecordedGateway.keepAliveAReply()]
            case 40: return [RecordedGateway.keepAliveBReply(to: datagram)]
            default: return []
            }
        }
    }

    /// 首轮「文件包」会收到 272 字节确认（0x02 = 0x10），里面也带一段 0x10 起的数据。
    /// 用这个模拟，守住「272 字节确认的 0x10 不许当 tail 抄回去」。
    private func filePacket272Responder() -> @Sendable (Data) -> [Data] {
        let success = RecordedGateway.loginSuccess()
        return { datagram in
            if Self.isLoginFrame(datagram) { return [success] }
            switch datagram.count {
            case 20: return [RecordedGateway.challengeReply()]
            case 38: return [RecordedGateway.keepAliveAReply()]
            case 40:
                if datagram[datagram.startIndex + 0x06] == 0x0F {   // 文件包（版本域 0F 27）
                    var reply = [UInt8](datagram)
                    reply[0x02] = 0x10
                    reply[0x03] = 0x01
                    reply.append(contentsOf: [UInt8](repeating: 0, count: 272 - 40))
                    reply.replaceSubrange(0x10..<0x14, with: [0x11, 0x22, 0x33, 0x44])
                    return [Data(reply)]
                }
                return [RecordedGateway.keepAliveBReply(to: datagram)]
            default: return []
            }
        }
    }

    @Test("主路径：idle → discovering → challenging → authenticating → online")
    func happyPath() async throws {
        let (engine, channel, _, _) = makeEngine(configuration: makeConfiguration(),
                                                 responder: wellBehavedResponder())
        let stream = await engine.events()
        let states = Atomic<[String]>([])
        let collector = Task {
            for await event in stream {
                if case .state(let state) = event {
                    states.withLock { $0.append(state.phase) }
                }
            }
        }
        await engine.start()
        try await expectEventually("进入 online") { await engine.currentState() == .online }
        try await Task.sleep(for: .milliseconds(30))
        collector.cancel()
        #expect(states.withLock { $0 } == ["idle", "discovering", "challenging", "authenticating", "online"])

        let sent = channel.sentFrames
        #expect(sent.first?.count == 20, "第一包必须是 20 字节 challenge")
        #expect(sent.contains { Self.isLoginFrame($0) }, "必须发过登录包")

        let params = try #require(channel.openParameters)
        #expect(params.localPort == 61440)
        #expect(params.localIP.description == "192.0.2.10")
        #expect(params.index == 12)
        #expect(params.remote.description == "10.100.61.3:61440")

        await engine.stop()
        #expect(await engine.currentState() == .idle)
    }

    @Test("过期的 challenge 应答必须被忽略（salt 只能取回显本次序号的那个）")
    func staleChallengeIsIgnored() async throws {
        let stale: Data = {
            var bytes = [UInt8](RecordedGateway.challengeReply(salt: "aaaabbbb"))
            bytes[0x02] = 0x11   // 不是本次序号
            bytes[0x03] = 0x11
            return Data(bytes)
        }()
        let fresh = RecordedGateway.challengeReply(salt: "49cb720f")
        let responder: @Sendable (Data) -> [Data] = { datagram in
            switch datagram.count {
            case 20: return [stale, fresh]   // 先塞一个过期的
            case let count where count > 300 && datagram.first == 0x03:
                return [RecordedGateway.loginSuccess()]
            case 38: return [RecordedGateway.keepAliveAReply()]
            case 40: return [RecordedGateway.keepAliveBReply(to: datagram)]
            default: return []
            }
        }
        let (engine, channel, _, _) = makeEngine(configuration: makeConfiguration(), responder: responder)
        await engine.start()
        try await expectEventually("进入 online") { await engine.currentState() == .online }

        let login = try #require(channel.sentFrames.first { Self.isLoginFrame($0) })
        let expected = DrcomCodec.digestA(password: "test-pass-2024",
                                          salt: [0x49, 0xCB, 0x72, 0x0F])
        #expect([UInt8](login[0x004..<0x014]) == expected,
                "登录摘要必须基于正确的 salt，过期应答的 salt 不能进来")
        await engine.stop()
    }

    @Test("静态 IP 漂移：报 staticConfigMismatch，不发任何认证包")
    func ipDrifted() async throws {
        var configuration = makeConfiguration()
        configuration.expectedIP = IPv4Address("192.0.2.99")   // 档案里记的旧地址
        let (engine, channel, factory, _) = makeEngine(configuration: configuration,
                                                       responder: { _ in [] })
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .staticConfigMismatch(field: "IP", expected: "192.0.2.99",
                                               actual: "192.0.2.10"))
        #expect(error.requiresUserAction)
        #expect(channel.sentFrames.isEmpty, "地址不对时发认证包毫无意义")
        #expect(factory.madeCount == 0)
        await engine.stop()
    }

    @Test("掩码漂移同样拦下")
    func maskDrifted() async throws {
        var configuration = makeConfiguration()
        configuration.expectedMask = "255.255.255.128"
        let (engine, _, _, _) = makeEngine(configuration: configuration, responder: { _ in [] })
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .staticConfigMismatch(field: "掩码", expected: "255.255.255.128",
                                               actual: "255.255.255.0"))
        await engine.stop()
    }

    @Test("登录被拒：原样展示服务器串，且不自动重试")
    func rejectionStopsRetrying() async throws {
        let (engine, channel, _, _) = makeEngine(
            configuration: makeConfiguration(),
            responder: { datagram in
                switch datagram.count {
                case 20:
                    // 回显本次序号：重试时序号会变，假网关必须跟着回显，否则会被判成网关无应答
                    // 序号在 0x02..0x03（大端）
                    let serial = UInt16(datagram[datagram.startIndex + 2]) << 8
                        | UInt16(datagram[datagram.startIndex + 3])
                    return [RecordedGateway.challengeReply(serial: serial)]

                default:
                    if Self.isLoginFrame(datagram) {
                        return [RecordedGateway.loginFailure(reason: "ldap auth error")]
                    }
                    return []
                }
            })
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else {
            Issue.record("状态应为 failed")
            return
        }
        guard case .rejected(let message) = error else {
            Issue.record("应为 rejected，实际：\(error)")
            return
        }
        #expect(message.contains("ldap auth error"), "服务器原文必须保留：\(message)")
        // ldap auth error 会先自动换 salt 重试两次（实测同一密码也会偶发），之后再交给用户
        #expect(channel.sentFrames.filter { Self.isLoginFrame($0) }.count <= 3)

        let loginCount = channel.sentFrames.filter { Self.isLoginFrame($0) }.count
        try await Task.sleep(for: .milliseconds(120))
        #expect(channel.sentFrames.filter { Self.isLoginFrame($0) }.count == loginCount,
                "认证失败必须停下来等用户，不许循环重登")
        await engine.stop()
    }

    @Test("账号冲突：进 failed(.accountInUse)，只尝试一次")
    func accountInUse() async throws {
        let (engine, channel, _, _) = makeEngine(
            configuration: makeConfiguration(),
            responder: { datagram in
                if datagram.count == 20 { return [RecordedGateway.challengeReply()] }
                if Self.isLoginFrame(datagram) {
                    return [RecordedGateway.loginFailure(reason: "account in use")]
                }
                return []
            })
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .accountInUse(reason: "account in use"))
        #expect(error.userMessage == "account in use")
        #expect(channel.sentFrames.filter { Self.isLoginFrame($0) }.count == 1)
        await engine.stop()
    }

    @Test("网关无应答：退避重试若干次后交给用户，不是无限循环")
    func gatewaySilent() async throws {
        let (engine, channel, _, _) = makeEngine(configuration: makeConfiguration(), responder: { _ in [] })
        let stream = await engine.events()
        let attempts = Atomic<[Int]>([])
        let collector = Task {
            for await event in stream {
                if case .state(.reconnecting(let attempt)) = event {
                    attempts.withLock { $0.append(attempt) }
                }
            }
        }
        await engine.start()

        try await expectEventually("进入 failed", timeout: .seconds(5)) {
            if case .failed = await engine.currentState() { true } else { false }
        }
        try await Task.sleep(for: .milliseconds(50))
        collector.cancel()

        let recorded = attempts.withLock { $0 }
        #expect(!recorded.isEmpty, "必须经过 reconnecting")
        #expect(recorded.last == 8, "最多重试 8 次，之后交回用户")
        #expect(channel.sentFrames.filter { $0.count == 20 }.count == 9,
                "首次 + 8 次重试，每次只发一个 challenge")
        await engine.stop()
    }

    /// 默认（非严格）：MAC 对不上也照样发，报文里用登记 MAC —— 由服务器裁定。
    @Test("MAC 对不上时仍然发认证（报文用登记 MAC），不把用户挡在门外")
    func macMismatchStillAuthenticates() async throws {
        let configuration = makeConfiguration()
        let (engine, channel, _, _) = makeEngine(
            configuration: configuration,
            provider: FakeInterfaceProvider(
                interfaces: [InterfaceSnapshot(name: "en7", index: 12, ipv4: "192.0.2.10",
                                               mac: "aa:bb:cc:dd:ee:ff", isWireless: false,
                                               isUp: true)],
                route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7"),
                configMethod: "Manual", gateway: "192.0.2.1"),
            responder: { datagram in
                if datagram.count == 20 { return [RecordedGateway.challengeReply()] }
                if Self.isLoginFrame(datagram) { return [RecordedGateway.loginSuccess()] }
                return []
            })
        await engine.start()
        try await expectEventually("发出登录包", timeout: .seconds(3)) {
            channel.sentFrames.contains { Self.isLoginFrame($0) }
        }
        let login = try #require(channel.sentFrames.first { Self.isLoginFrame($0) })
        // 登记 MAC 是 02:00:00:00:00:01，即使网卡是 aa:bb:...，报文也用登记值
        let macOffset = 322 + makeConfiguration().password.utf8.count
        #expect([UInt8](login[macOffset..<(macOffset + 6)]) == [0x02, 0x00, 0x00, 0x00, 0x00, 0x01])
        await engine.stop()
    }

    @Test("严格模式（strictMACCheck）：MAC 不匹配就不发任何报文")
    func macMismatchStrict() async throws {
        var configuration = makeConfiguration()
        configuration.strictMACCheck = true
        let (engine, channel, factory, _) = makeEngine(
            configuration: configuration,
            provider: FakeInterfaceProvider(
                interfaces: [InterfaceSnapshot(name: "en7", index: 12, ipv4: "192.0.2.10",
                                               mac: "aa:bb:cc:dd:ee:ff", isWireless: false,
                                               isUp: true)],
                route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7"),
                configMethod: "Manual", gateway: "192.0.2.1"),
            responder: { _ in [] })

        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .macMismatch(expected: "02:00:00:00:00:01", actual: "aa:bb:cc:dd:ee:ff"))
        #expect(factory.madeCount == 0, "严格模式下连通道都不该建")
        #expect(channel.sentFrames.isEmpty)
        await engine.stop()
    }

    @Test("系统还是 DHCP：直接报错，不发包")
    func dhcpAssigned() async throws {
        var provider = FakeInterfaceProvider.wired
        provider.configMethod = "DHCP"
        let (engine, channel, factory, _) = makeEngine(configuration: makeConfiguration(),
                                                       provider: provider,
                                                       responder: { _ in [] })
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .dhcpAssigned(interface: "en7"))
        #expect(channel.sentFrames.isEmpty)
        #expect(factory.madeCount == 0)
        await engine.stop()
    }

    @Test("被代理 TUN 接管：报 capturedByTunnel，不发包")
    func capturedByTunnel() async throws {
        var provider = FakeInterfaceProvider.wired
        provider.route = RouteInfo(destination: "10.100.61.3", gateway: "198.18.0.1", interface: "utun4")
        let (engine, channel, _, _) = makeEngine(configuration: makeConfiguration(),
                                                 provider: provider,
                                                 responder: { _ in [] })
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .capturedByTunnel(interface: "utun4"))
        #expect(channel.sentFrames.isEmpty)
        await engine.stop()
    }

    @Test("网卡拔掉：立刻 failed，不进退避空转（等 PathMonitor 触发重来）")
    func adapterUnplugged() async throws {
        let (engine, channel, factory, _) = makeEngine(
            configuration: makeConfiguration(),
            provider: FakeInterfaceProvider(interfaces: [], route: nil, configMethod: nil, gateway: nil),
            responder: { _ in [] })
        let stream = await engine.events()
        let reconnects = Atomic<[Int]>([])
        let collector = Task {
            for await event in stream {
                if case .state(.reconnecting(let attempt)) = event {
                    reconnects.withLock { $0.append(attempt) }
                }
            }
        }
        await engine.start()
        try await expectEventually("进入 failed") {
            if case .failed = await engine.currentState() { true } else { false }
        }
        try await Task.sleep(for: .milliseconds(80))
        collector.cancel()

        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error == .adapterUnplugged(interface: "en*"))
        #expect(error.awaitsPathChange, "这类错误要等网络变化，而不是退避")
        #expect(reconnects.withLock { $0 }.isEmpty, "拔网线不该走 reconnecting 空转")
        #expect(factory.madeCount == 0, "没有网卡就不该建通道")
        #expect(channel.sentFrames.isEmpty)
        await engine.stop()
    }

    @Test("保活连续 3 轮无应答 → reconnecting（而不是死撑）")
    func keepAliveMisses() async throws {
        // 登录能成功，但登录之后网关不再应答保活 —— 模拟被踢线。
        let responder: @Sendable (Data) -> [Data] = { datagram in
            switch datagram.count {
            case 20: return [RecordedGateway.challengeReply()]
            case 342: return [RecordedGateway.loginSuccess()]
            default: return []
            }
        }
        let (engine, _, _, _) = makeEngine(configuration: makeConfiguration(keepAliveInterval: .seconds(1)),
                                          responder: responder)
        let stream = await engine.events()
        let sawReconnecting = Atomic(false)
        let collector = Task {
            for await event in stream {
                if case .state(.reconnecting) = event { sawReconnecting.withLock { $0 = true } }
            }
        }

        await engine.start()
        try await expectEventually("掉线后进入 reconnecting", timeout: .seconds(10)) {
            sawReconnecting.withLock { $0 }
        }
        collector.cancel()
        await engine.stop()
    }

    @Test("stop() 之后不再产生任何状态事件（旧任务不许写新状态）")
    func stopIsSilent() async throws {
        let (engine, channel, _, _) = makeEngine(configuration: makeConfiguration(),
                                                 responder: wellBehavedResponder())
        await engine.start()
        try await expectEventually("进入 online") { await engine.currentState() == .online }
        await engine.stop()
        // stop() 是异步收尾：并发满载时可能晚一拍才写 idle，这里等到它稳定
        try await expectEventually("停止后回到 idle", timeout: .seconds(2)) {
            await engine.currentState() == .idle
        }
        let sentAfterStop = channel.sentFrames.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(channel.sentFrames.count == sentAfterStop, "stop 之后不许再发包")
        #expect(channel.isClosed)
    }

    @Test("272 字节文件包确认里的 0x10 不许当 tail 抄进保活 B")
    func keepAliveBFileReplyDoesNotPoisonTail() async throws {
        let (engine, channel, _, _) = makeEngine(
            configuration: makeConfiguration(keepAliveInterval: .seconds(1)),
            responder: filePacket272Responder())
        await engine.start()
        try await expectEventually("进入 online") { await engine.currentState() == .online }
        try await expectEventually("收到至少两对 B", timeout: .seconds(10)) {
            channel.sentFrames.filter { $0.count == 40 }.count >= 6
        }
        await engine.stop()

        let bFrames = channel.sentFrames.filter { $0.count == 40 }
        let tails = bFrames.prefix(6).map { Array($0[0x10...0x13]) }
        #expect(!tails.contains([0x11, 0x22, 0x33, 0x44]),
                "272 字节确认不是 A/C 应答，它的 0x10 不能进请求，实际 \(tails)")
    }

    @Test("保活 B：首轮发文件包，之后每轮 A(01)/C(03) 交替，计数器递增")
    func keepAliveSequencing() async throws {
        let (engine, channel, _, _) = makeEngine(configuration: makeConfiguration(keepAliveInterval: .seconds(1)),
                                                 responder: filePacket272Responder())
        await engine.start()
        try await expectEventually("进入 online") { await engine.currentState() == .online }
        // 文件包 + 两轮 A/C 至少 5 个 B 包
        try await expectEventually("收到至少 5 个 B 包", timeout: .seconds(10)) {
            channel.sentFrames.contains { $0.count == 38 } &&
            channel.sentFrames.filter { $0.count == 40 }.count >= 5
        }
        await engine.stop()

        let frameTypes = channel.sentFrames.map { $0.count }
        #expect(frameTypes.first == 20)
        #expect(frameTypes.contains { $0 > 300 })
        #expect(frameTypes.contains(38), "必须有 A 型（38 字节）")

        let bFrames = channel.sentFrames.filter { $0.count == 40 }
        // 首包是文件包：版本域 0F 27
        #expect(Array(bFrames[0][0x06..<0x08]) == [0x0F, 0x27], "首轮必须发文件包")
        // 之后 [0x05] 是包类型：01=A、03=C —— 这一列以前是 01/03/05/07 的「序号」，
        // 从 05 起网关直接丢包，保活 B 整场超时、十几分钟后掉线。
        let afterFile = bFrames.dropFirst()
        let types = afterFile.prefix(4).map { $0[0x05] }
        #expect(types.elementsEqual([0x01, 0x03, 0x01, 0x03]),
                "包类型必须 01/03 交替，实际 \(types)")
        // 计数器 [0x01] 每包 +1
        let counters = bFrames.prefix(5).map { $0[0x01] }
        #expect(counters.elementsEqual([0x05, 0x06, 0x07, 0x08, 0x09]),
                "计数器应每包 +1，实际 \(counters)")
        // C 包必须带上一包应答里的 tail
        let cPackets = bFrames.dropFirst().filter { $0[0x05] == 0x03 }
        if let c = cPackets.first {
            #expect(Array(c[0x10...0x13]) != [0, 0, 0, 0], "C 包必须带回 tail")
        }
    }

    @Test("保活 B 整场收不到回执也不判掉线（会话由保活 A 决定）")
    func keepAliveBFailureDoesNotDropSession() async throws {
        // 只应 A，40 字节的 B 包一个都不回 —— 真机上就是这个样子。
        let responder: @Sendable (Data) -> [Data] = { datagram in
            if Self.isLoginFrame(datagram) { return [RecordedGateway.loginSuccess()] }
            switch datagram.count {
            case 20: return [RecordedGateway.challengeReply()]
            case 38: return [RecordedGateway.keepAliveAReply()]
            default: return []
            }
        }
        let (engine, channel, _, _) = makeEngine(
            configuration: makeConfiguration(keepAliveInterval: .seconds(1)),
            responder: responder)
        let stream = await engine.events()
        let sawReconnecting = Atomic(false)
        let collector = Task {
            for await event in stream {
                if case .state(.reconnecting) = event { sawReconnecting.withLock { $0 = true } }
            }
        }
        await engine.start()
        try await expectEventually("进入 online") { await engine.currentState() == .online }
        try await expectEventually("已经发过 B 包", timeout: .seconds(10)) {
            channel.sentFrames.contains { $0.count == 40 }
        }
        // 再给几轮时间：B 一直超时，但 A 正常，状态必须还是 online
        try await Task.sleep(for: .milliseconds(600))
        #expect(await engine.currentState() == .online)
        #expect(sawReconnecting.withLock { $0 } == false, "B 无应答不该把会话判掉线")
        collector.cancel()
        await engine.stop()
    }
}

/// 测试用的小锁包装（计数器）。
final class Atomic<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private final class LoginCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}

@Suite("0x15 视为凭据被拒（不再换报文版本）")
struct LoginVariantFallbackTests {
    @Test("0x15 只重试有限次，然后进 failed 等用户重输密码")
    func fallsBackToLegacy() async throws {
        let counter = LoginCounter()
        let channel = FakeChannel { datagram in
            if datagram.count == 20 {
                let serial = UInt16(datagram[datagram.startIndex + 2]) << 8
                    | UInt16(datagram[datagram.startIndex + 3])
                return [RecordedGateway.challengeReply(serial: serial)]
            }
            if datagram.count > 300, datagram.first == 0x03 {
                _ = counter.next()
                return [RecordedGateway.loginFailure(reason: "ldap auth error", code: 0x15)]
            }
            return []
        }
        let configuration = EngineConfiguration(
            account: "20230001", password: "test-pass-2024", hostname: "test-mac.local",
            registeredMAC: MACAddress("02:00:00:00:00:01"),
            keepAliveInterval: .seconds(10))
        let engine = DrcomEngine(configuration: configuration,
                                 codec: DrcomCodec(randomness: SeededRandomSource(seed: 7)),
                                 channelFactory: RecordingChannelFactory(channel: channel),
                                 interfaces: FakeInterfaceProvider.wired,
                                 clock: FakeClock(),
                                 backoff: Backoff())
        await engine.start()
        try await expectEventually("进入 failed", timeout: .seconds(4)) {
            if case .failed = await engine.currentState() { true } else { false }
        }
        guard case .failed(let error) = await engine.currentState() else { return }
        #expect(error.isCredentialRejection, "0x15 应当被当成凭据被拒")
        let logins = channel.sentFrames.filter { $0.count > 300 && $0.first == 0x03 }
        #expect(logins.count <= 3, "只允许换 salt 少量重试，不能死循环")
        #expect(Set(logins.map(\.count)).count == 1, "不再切换报文版本")
        await engine.stop()
    }
}

@Suite("拔网线后反复重试不应该崩")
struct UnpluggedRetryTests {
    @Test("没有物理网口时：进入 failed，重试多次仍然稳定")
    func retryWithoutInterfaces() async throws {
        let channel = FakeChannel { _ in [] }
        let provider = FakeInterfaceProvider(interfaces: [], route: nil,
                                            configMethod: nil, gateway: nil)
        let engine = DrcomEngine(
            configuration: EngineConfiguration(account: "20230001", password: "test-pass-2024",
                                               hostname: "test-mac.local"),
            codec: DrcomCodec(randomness: SeededRandomSource(seed: 5)),
            channelFactory: RecordingChannelFactory(channel: channel),
            interfaces: provider,
            clock: FakeClock())
        for _ in 0..<5 {
            await engine.start()
            try await Task.sleep(for: .milliseconds(120))
            await engine.retry()
            try await Task.sleep(for: .milliseconds(120))
        }
        await engine.stop()
        // 能走到这里就说明没有崩溃；状态应停在 failed/idle，而不是 online
        let state = await engine.currentState()
        #expect(state != .online)
    }
}
