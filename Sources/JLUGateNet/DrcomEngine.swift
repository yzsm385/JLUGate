import Foundation
import JLUGateCore

public struct EngineConfiguration: Sendable {
    public var server: IPv4Address
    public var serverPort: UInt16
    public var localPort: UInt16
    public var account: String
    public var password: String
    /// 学校平台登记的 MAC（不是"当前接口 MAC"）。为 nil 时不校验。
    public var registeredMAC: MACAddress?
    public var hostname: String
    /// 用户手动锁定的接口名（可选）。
    public var interfaceLock: String?
    /// 严格模式：MAC 与登记值不一致就报错（默认关闭——**应由服务器裁定**，
    /// 客户端预检只作为提示，不能把用户卡在门外）。
    public var strictMACCheck: Bool = false
    /// 保活收不到应答时，用一次真实网络探测来判定"到底断没断"。
    /// 有些网关不回保活应答但会话仍然有效——只看应答会把在线误判成离线。
    public var livenessCheck: (@Sendable (InterfaceSnapshot) async -> Bool)?
    /// 系统给网卡用了私有/随机 MAC 时，允许认证报文里填"登记的 MAC"。
    /// 只影响报文内容，不改网卡本身（UDP 认证服务器只比对报文里的 MAC）。
    public var useRegisteredMACForAuth: Bool = false
    /// 档案里登记的静态 IP / 掩码。与接口实际值不符时报"IP 已漂移"，
    /// 而不是发一串注定失败的认证包（PLAN §6.3）。
    public var expectedIP: IPv4Address?
    /// 排障开关：打印完整登录报文（默认关；报文里含账号与 MAC）
    public var verboseAuthLogging: Bool = false
    /// 自动选口时是否"有线优先"（JLU.WIFI 模式要设 false，否则会被有线抢走）
    public var preferWired: Bool = true
    public var expectedMask: String?

    public var challengeSubtype: UInt8
    public var challengeTimeout: Duration
    public var loginTimeout: Duration
    public var keepAliveInterval: Duration
    public var missTolerance: Int
    /// 唤醒后先静默 2s 再 discover（PLAN §8.3）。
    public var wakeDelay: Duration

    public init(account: String, password: String, hostname: String,
                registeredMAC: MACAddress? = nil, interfaceLock: String? = nil,
                expectedIP: IPv4Address? = nil, expectedMask: String? = nil,
                useRegisteredMACForAuth: Bool = false,
                verboseAuthLogging: Bool = false,
                preferWired: Bool = true,
                strictMACCheck: Bool = false,
                server: IPv4Address = PacketLayout.defaultServer,
                serverPort: UInt16 = PacketLayout.serverPort,
                localPort: UInt16 = PacketLayout.localPort,
                challengeSubtype: UInt8 = PacketLayout.Challenge.firstSubtype,
                challengeTimeout: Duration = .seconds(3),
                loginTimeout: Duration = .seconds(5),
                keepAliveInterval: Duration = .seconds(10),
                missTolerance: Int = 3,
                wakeDelay: Duration = .seconds(2),
                livenessCheck: (@Sendable (InterfaceSnapshot) async -> Bool)? = nil) {
        self.account = account
        self.password = password
        self.hostname = hostname
        self.registeredMAC = registeredMAC
        self.interfaceLock = interfaceLock
        self.expectedIP = expectedIP
        self.expectedMask = expectedMask
        self.useRegisteredMACForAuth = useRegisteredMACForAuth
        self.verboseAuthLogging = verboseAuthLogging
        self.preferWired = preferWired
        self.strictMACCheck = strictMACCheck
        self.server = server
        self.serverPort = serverPort
        self.localPort = localPort
        self.challengeSubtype = challengeSubtype
        self.challengeTimeout = challengeTimeout
        self.loginTimeout = loginTimeout
        self.keepAliveInterval = keepAliveInterval
        self.missTolerance = missTolerance
        self.livenessCheck = livenessCheck
        self.wakeDelay = wakeDelay
    }
}

/// 一次会话的不可变上下文（接口、IP、序号、salt）。
public struct SessionContext: Sendable {
    public let interface: InterfaceSnapshot
    public let localIP: IPv4Address
    public let serial: UInt16
    public let salt: [UInt8]
    /// 仅在 `authenticate` 内部存活。
    let channel: any DatagramChannel

    init(interface: InterfaceSnapshot, localIP: IPv4Address, serial: UInt16,
         salt: [UInt8], channel: any DatagramChannel) {
        self.interface = interface
        self.localIP = localIP
        self.serial = serial
        self.salt = salt
        self.channel = channel
    }
}

/// Dr.Com 认证引擎：`actor` + `epoch` 世代号（PLAN §7）。
///
/// 状态流转：`idle → discovering → challenging → authenticating → online`，
/// 出问题进 `reconnecting`（带退避）或 `failed`（等用户）。
/// 所有 Task 捕获进入时的 epoch，写状态前校验；旧任务一律不许改新状态。
public actor DrcomEngine {
    public enum Event: Sendable, Equatable {
        case state(AuthState)
        case session(account: String, clientIP: String?, session: UInt16)
        case traffic(secondsOnline: UInt32, stats: [UInt32])
        case log(String)
    }

    private let configuration: EngineConfiguration
    private let codec: DrcomCodec
    private let channelFactory: any ChannelFactory
    private let interfaces: any InterfaceProvider
    private let clock: any Clock
    private let backoff: Backoff

    private var state: AuthState = .idle
    private var epoch: UInt64 = 0
    private var runTask: Task<Void, Never>?
    private var channel: (any DatagramChannel)?
    private var serialCounter: UInt16 = 0
    /// challenge 应答里服务器给的会话别名（保活 B 要带回去）。
    private var serverSessionID: UInt16 = 0
    /// 已经记过的"未知报文"签名：同一种只记一次，避免每 20 秒刷一行 hex
    private var loggedUnknownSignatures: Set<String> = []
    private var ticket: SessionTicket?
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var lastError: DrcomError?
    private var sessionStartedAt: ContinuousClock.Instant?

    public init(configuration: EngineConfiguration,
                codec: DrcomCodec = DrcomCodec(),
                channelFactory: any ChannelFactory = BSDChannelFactory(),
                interfaces: any InterfaceProvider = SystemInterfaceProvider(),
                clock: any Clock = SystemClock(),
                backoff: Backoff = Backoff()) {
        self.configuration = configuration
        self.codec = codec
        self.channelFactory = channelFactory
        self.interfaces = interfaces
        self.clock = clock
        self.backoff = backoff
    }

    // MARK: 对外接口

    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(.state(state))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func currentState() -> AuthState { state }

    public func currentSession() -> (ticket: SessionTicket?, error: DrcomError?) {
        (ticket, lastError)
    }

    public func start() {
        guard runTask == nil else { return }
        let epoch = nextEpoch()
        lastError = nil
        runTask = Task { [weak self] in
            await self?.runLoop(epoch: epoch)
        }
    }

    public func stop() async {
        _ = nextEpoch()
        runTask?.cancel()
        runTask = nil
        await teardown()
        setState(.idle)
    }

    /// 用户点"重试"（从 `failed` 回到 discover）。账号冲突场景必须由用户触发。
    public func retry() async {
        await stop()
        start()
    }

    /// 睡眠：关通道、取消全部任务，**不发 Logout**（PLAN §8.3 第 1 条）。
    public func suspendForSleep() async {
        await stop()
    }

    /// 唤醒：先静默，再重新获取一切（接口索引/MAC/IP/路由都可能变）。
    public func resumeAfterWake() async {
        await stop()
        try? await clock.sleep(for: configuration.wakeDelay)
        start()
    }

    // MARK: 主循环

    private func runLoop(epoch: UInt64) async {
        var attempt = 0
        var credentialRetries = 0
        var loginVariant: LoginVariant = .current
        while isCurrent(epoch) && !Task.isCancelled {
            do {
                let context = try await discover(epoch: epoch)
                let ticket = try await authenticate(context: context, epoch: epoch,
                                                    variant: loginVariant)
                attempt = 0
                credentialRetries = 0
                try await stayOnline(context: context, ticket: ticket, epoch: epoch)
            } catch let error as DrcomError {
                await teardown()
                guard isCurrent(epoch) else { return }

                if error == .cancelled { return }
                lastError = error
                // 这条在真机排障时最值钱：把"为什么重连"的原始原因写进日志
                emit(.log("认证失败：\(error.userMessage)（\(error)）"))

                // 拔网线 / 网卡暂时没地址：停下等网络变化，不做无意义的退避空转（PLAN §6.3）
                if error.awaitsPathChange {
                    setState(.failed(error))
                    return
                }

                // ldap auth error：实测同一密码也会偶发（账号在别处在线 / 服务器忙），
                // 换一个新 salt 重试两次；仍失败才交给用户。
                if error.isCredentialRejection, credentialRetries < 2 {
                    credentialRetries += 1
                    emit(.log("服务器回 ldap auth error：换新 salt 重试第 \(credentialRetries) 次"))
                    try? await clock.sleep(for: .seconds(2))
                    continue
                }

                // 账号冲突 / MAC / DHCP / TUN / 服务器明确拒绝：一律停下等用户
                // （CHECKLIST §12：认证失败不许自动重试，否则会被打成顶号乒乓）
                if error.requiresUserAction || !error.isRetryable {
                    setState(.failed(error))
                    return
                }
                attempt += 1
                if backoff.shouldGiveUp(attempt: attempt) {
                    setState(.failed(error))
                    return
                }
                setState(.reconnecting(attempt: attempt))
                do {
                    try await clock.sleep(for: backoff.delay(attempt: attempt))
                } catch {
                    return
                }
            } catch {
                await teardown()
                guard isCurrent(epoch) else { return }
                lastError = .channelFailure("\(error)")
                attempt += 1
                if backoff.shouldGiveUp(attempt: attempt) {
                    setState(.failed(.channelFailure("\(error)")))
                    return
                }
                setState(.reconnecting(attempt: attempt))
                try? await clock.sleep(for: backoff.delay(attempt: attempt))
            }
        }
        if isCurrent(epoch) { runTask = nil }
    }

    // MARK: discovering

    private func discover(epoch: UInt64) async throws -> SessionContext {
        setState(.discovering)
        guard isCurrent(epoch) else { throw DrcomError.cancelled }

        var candidates = interfaces.physicalInterfaces()
        if let lock = configuration.interfaceLock {
            candidates = candidates.filter { $0.name == lock }
        }
        guard !candidates.isEmpty else {
            throw DrcomError.adapterUnplugged(interface: configuration.interfaceLock ?? "en*")
        }

        let chosen = try chooseInterface(from: candidates)
        guard let localIP = chosen.ipv4Address else {
            throw DrcomError.interfaceHasNoIPv4(interface: chosen.name)
        }

        if let method = interfaces.configMethod(of: chosen.name),
           method.lowercased() != "manual" {
            throw DrcomError.dhcpAssigned(interface: chosen.name)
        }

        // 静态地址漂移：接口在、也是 Manual，但地址不是档案里那个（换口/换网后最常见）
        if let expected = configuration.expectedIP, localIP != expected {
            throw DrcomError.staticConfigMismatch(field: "IP", expected: expected.description,
                                                  actual: localIP.description)
        }
        if let expectedMask = configuration.expectedMask,
           let actualMask = chosen.netmask,
           !expectedMask.isEmpty, actualMask != expectedMask {
            throw DrcomError.staticConfigMismatch(field: "掩码", expected: expectedMask,
                                                  actual: actualMask)
        }

        if let route = interfaces.route(to: configuration.server), route.isTunnel {
            throw DrcomError.capturedByTunnel(interface: route.interface ?? "tunnel")
        }

        serialCounter = nextSerial()
        return SessionContext(interface: chosen, localIP: localIP, serial: serialCounter,
                              salt: [], channel: channelFactory.makeChannel())
    }

    /// 选口：MAC 命中 +8 → 有线 +2 → 有默认网关 +1（challenge 探测 +4 留待 M2.5，见 progress.md）。
    private func chooseInterface(from candidates: [InterfaceSnapshot]) throws -> InterfaceSnapshot {
        let usable = candidates.filter(\.isUsableForAuthentication)
        let pool = usable.isEmpty ? candidates : usable
        // 一个网卡都没有：这是拔线/没地址，绝不能对着空数组 first!（会直接崩）
        guard !pool.isEmpty else {
            throw DrcomError.interfaceHasNoIPv4(interface: configuration.interfaceLock ?? "en*")
        }

        if configuration.useRegisteredMACForAuth {
            // 系统换成了私有 MAC，但报文按登记 MAC 填：不在这里拦，直接挑最合适的口
            return pool.sorted(by: scoreSort).first ?? pool[0]
        }

        if let registered = configuration.registeredMAC {
            // 与"出厂 MAC"比对：系统换成私有 MAC 时，学校登记的仍是出厂值
            let matched = pool.filter { $0.macForAuthentication?.matches(registered) == true }
            guard !matched.isEmpty else {
                let actual = pool.first?.macForAuthentication?.description ?? "无"
                let listing = pool.map { "\($0.name)=\($0.macForAuthentication?.description ?? "—")" }
                    .joined(separator: "、")
                emit(.log("没有网卡的 MAC 等于登记值 \(registered)（现有：\(listing)）；"
                          + "先用最合适的网卡、报文按登记 MAC 发送，由服务器裁定"))
                if configuration.strictMACCheck {
                    throw DrcomError.macMismatch(expected: registered.description, actual: actual)
                }
                // 非严格模式：继续，登录报文里用登记 MAC
                return pool.sorted(by: scoreSort).first ?? pool[0]
            }
            return matched.sorted(by: scoreSort).first ?? pool[0]
        }
        return pool.sorted(by: scoreSort).first ?? pool[0]
    }

    private func scoreSort(_ lhs: InterfaceSnapshot, _ rhs: InterfaceSnapshot) -> Bool {
        let lScore = (lhs.isWireless ? 0 : 2) + ((lhs.ipv4 != nil) ? 1 : 0)
        let rScore = (rhs.isWireless ? 0 : 2) + ((rhs.ipv4 != nil) ? 1 : 0)
        if lScore != rScore { return lScore > rScore }
        return lhs.index < rhs.index
    }

    // MARK: challenging + authenticating

    private func authenticate(context: SessionContext, epoch: UInt64,
                              variant: LoginVariant = .current) async throws -> SessionTicket {
        let channel = context.channel
        self.channel = channel
        try await channel.open(
            localIP: context.localIP,
            localPort: configuration.localPort,
            remote: IPv4Endpoint(host: configuration.server, port: configuration.serverPort),
            interfaceIndex: context.interface.index)

        setState(.challenging)
        let challenge = try codec.makeChallenge(serial: context.serial,
                                                subtype: configuration.challengeSubtype)
        emit(.log("challenge serial=0x\(String(format: "%04x", context.serial)) 长度=\(challenge.count)"))
        try await channel.send(challenge)

        let salt: [UInt8]
        do {
            // 只认**回显本次序号**的那一个：一次登录里可能连着来好几个 challenge，
            // 取错一个 salt，MD5 永远算不对，服务器只会回 ldap auth error（CHECKLIST §4 的坑）。
            let serial = context.serial
            let incoming = try await receive(matching: { frame in
                if case .challengeReply(let reply) = frame { reply.serial == serial } else { false }
            }, timeout: configuration.challengeTimeout)
            guard case .challengeReply(let reply) = incoming.frame else {
                throw DrcomError.gatewayUnreachable(host: configuration.server.description)
            }
            salt = reply.salt
            serverSessionID = reply.sessionID
            emit(.log("收到 challenge 应答：salt=\(Hex.string(salt)) 会话=\(String(format: "0x%04x", reply.sessionID))"))
            emit(.log("challenge 应答原文（前 48 字节）=\(Hex.string(incoming.payload, limit: 48))"))
        } catch let error as DrcomError where error == .cancelled {
            throw error
        } catch {
            throw DrcomError.gatewayUnreachable(host: configuration.server.description)
        }
        guard isCurrent(epoch) else { throw DrcomError.cancelled }

        setState(.authenticating)
        // 选了这块网卡但 MAC 对不上登记值时，报文按登记值发（官方客户端也是这么做的），
        // 由服务器裁定，不由客户端拦人。
        let interfaceMatchesRegistered = configuration.registeredMAC.map {
            context.interface.macForAuthentication?.matches($0) == true
        } ?? true
        let loginContext = LoginContext(
            account: configuration.account,
            password: configuration.password,
            salt: salt,
            clientIP: context.localIP,
            linkLocalIP: context.interface.linkLocalIPv4.flatMap(IPv4Address.init),
            hostname: configuration.hostname,
            mac: (configuration.useRegisteredMACForAuth || !interfaceMatchesRegistered ? configuration.registeredMAC : nil)
                ?? context.interface.macForAuthentication
                ?? MACAddress(bytes: [0, 0, 0, 0, 0, 0])!)
        let login = try codec.makeLogin(loginContext, variant: variant)
        let digest = DrcomCodec.digestA(password: configuration.password, salt: salt)
        // 报文里有账号与 MAC：默认不落盘；仅调试模式打印，且账号已抹掉
        if configuration.verboseAuthLogging {
            let hex = Redact.scrubAccount(in: Hex.string(login), account: configuration.account)
            emit(.log("登录包原文=\(hex)"))
        }
        emit(.log("发送登录包：\(login.count) 字节，摘要A=\(Hex.string(digest, limit: 8))…，"
                  + "账号=\(Redact.account(configuration.account))，接口 MAC=\(Redact.mac("\(loginContext.mac)"))"))
        try await channel.send(login)

        let incoming = try await receive(matching: { frame in
            switch frame {
            case .loginSuccess, .loginFailure: true
            default: false
            }
        }, timeout: configuration.loginTimeout)

        guard isCurrent(epoch) else { throw DrcomError.cancelled }

        switch incoming.frame {
        case .loginSuccess(let parsed):
            let session = sessionBase(from: context.serial)
            var ticket = parsed
            ticket.account = configuration.account
            ticket.digestA = DrcomCodec.digestA(password: configuration.password, salt: salt)
            ticket.session = session
            self.ticket = ticket
            sessionStartedAt = clock.now()
            setState(.online)
            emit(.session(account: ticket.account, clientIP: ticket.clientIP.description,
                          session: ticket.session))
            return ticket
        case .loginFailure(let reason):
            let code = codec.parseLoginFailureCode(Data(incoming.payload))
            let mapped = code.flatMap(JLULoginError.from(code:))
            let codeText = code.map { String(format: "0x%02X", $0) } ?? "无"
            emit(.log("登录被服务器拒绝：\"\(reason)\" 错误码=\(codeText)"
                      + (mapped.map { "（\($0.title)：\($0.advice)）" } ?? "")
                      + "（原始帧前 32 字节=\(Hex.string(incoming.payload, limit: 32))）"))
            throw DrcomError.classifyRejection(reason, code: code)
        default:
            // 把"服务器到底回了什么"记下来：这是判定登录成功/失败的关键证据
            emit(.log("登录后收到未识别的报文（可能是成功/失败的变体）："
                      + "\(incoming.payload.count) 字节，前 24 字节=\(Hex.string(incoming.payload, limit: 24))"))
            throw DrcomError.timeout(stage: "login")
        }
    }

    // MARK: online（保活）

    private func stayOnline(context: SessionContext, ticket initialTicket: SessionTicket,
                            epoch: UInt64) async throws {
        var ticket = initialTicket
        // A/B 交替：奇数轮发 A（0xFF），偶数轮发 B（A/C 两个包）。
        var round: UInt8 = 0x04
        // B 包的计数器（0x01）：每发一个 B 包 +1。抓包里第一对是 05/06，这里同样从 0x04 起。
        var bCounter: UInt8 = 0x04
        var misses = 0
        var bTimeouts = 0
        var loggedFirstB = false
        /// 上一包应答里的 tail（0x10–0x13）：C 包要原样带回。
        var tail: UInt32 = 0
        /// 每个会话只在第一轮 B 发一次「文件包」（版本域 `0F 27`），网关回 272 字节确认。
        var sentFilePacket = false
        /// 保活 B 自检：本会话发了几包、回了几包（写进诊断，一眼看出方言对不对）
        var bSent = 0
        var bAnswered = 0
        var bLoggedVerdict = false
        /// 诊断用：第一对 A/C 报文和第一条应答的完整字节，各记一次（真机对照官方抓包要用）
        var loggedFirstC = false
        var loggedFirstBReply = false
        /// 方言兜底：主格式（0x05=包类型 01/03）整轮没人应时，自动换一次旧格式（0x05=序号 05/07）。
        /// 只在本会话从头到尾一包都没被应答时触发，所以不影响已经工作正常的网关。
        var bLegacyTypes = false
        var bProbesLeft = 1

        while isCurrent(epoch) && !Task.isCancelled {
            round &+= 1
            let kind: KeepAliveKind = (round % 2 == 1) ? .a : .b
            do {
                switch kind {
                case .a:
                    var current = ticket
                    current.session = currentSessionCounter(base: ticket.session)
                    let datagram = try codec.makeKeepAliveA(ticket: current, server: configuration.server)
                    try await context.channel.send(datagram)
                    let incoming = try await receive(matching: { frame in
                        if case .keepAliveAReply = frame { true } else { false }
                    }, timeout: configuration.keepAliveInterval)
                    guard case .keepAliveAReply(let status) = incoming.frame else {
                        throw DrcomError.timeout(stage: "keepAliveA")
                    }
                    ticket = current
                    self.ticket = current
                    emit(.traffic(secondsOnline: status.secondsOnline, stats: status.stats))
                    emit(.log("保活A 应答 在线=\(status.secondsOnline)s stats=\(status.stats)"))
                    misses = 0
                case .b:
                    // 保活 B = 「A 包（类型 1）→ C 包（类型 3）」一问一答，字段语义：
                    //   0x01 计数器  0x05 类型（1=A, 3=C）  0x06–0x07 版本
                    //   0x10–0x13 tail（上一包应答带回）  0x18 校验  0x1C 客户端 IP
                    // 以前把 0x05 当成「请求/应答共用的自增序号」发 01/03/05/07…：
                    // 第一对刚好等于合法类型，网关应了；之后类型变成 05，网关直接丢包，
                    // 于是「保活 B 只回前两包、整场超时」，会话十几分钟后被服务端释放。
                    do {
                        if !sentFilePacket {
                            sentFilePacket = true
                            bCounter &+= 1
                            let file = KeepAliveBContext(
                                type: PacketLayout.KeepAliveB.typeA,
                                counter: bCounter,
                                session: serverSessionID,
                                timestamp: currentTimestamp(),
                                tail: 0, check: 0,
                                isFilePacket: true)
                            let datagram = try codec.makeKeepAliveB(file)
                            try await context.channel.send(datagram)
                            emit(.log(String(format: "保活B 文件包 发送 counter=0x%02X size=%d",
                                             Int(bCounter), datagram.count)))
                            do {
                                let ack = try await receive(matching: { frame in
                                    switch frame {
                                    case .keepAliveBRequest, .keepAliveBReply: true
                                    default: false
                                    }
                                }, timeout: .seconds(2))
                                let marker = ack.payload.count > 2
                                    ? ack.payload[ack.payload.startIndex + 2] : 0
                                emit(.log(String(format: "保活B 文件包 应答：%d 字节 0x02=0x%02X",
                                                 ack.payload.count, Int(marker))))
                            } catch let error as DrcomError where error == .cancelled {
                                throw error
                            } catch {
                                emit(.log("保活B 文件包 无应答（不判定掉线，继续 A/C）"))
                            }
                        }
                        for packetIndex in 0..<2 {
                            bCounter &+= 1
                            // 主格式：[0x05] = 包类型（A=01 / C=03）
                            // 旧格式：[0x05] = 序号（05 / 07）—— 只有主格式整轮没人应时才试
                            let type: UInt8
                            if bLegacyTypes {
                                type = packetIndex == 0 ? 0x05 : 0x07
                            } else {
                                type = packetIndex == 0
                                    ? PacketLayout.KeepAliveB.typeA
                                    : PacketLayout.KeepAliveB.typeC
                            }
                            let bContext = KeepAliveBContext(
                                type: type,
                                counter: bCounter,
                                session: serverSessionID,
                                timestamp: currentTimestamp(),
                                tail: tail,
                                // 抓包里 A 包校验为 0，只有 C 包带校验字
                                check: packetIndex == 0 ? 0 : UInt32.random(in: 0...UInt32.max),
                                clientIP: packetIndex == 1 ? ticket.clientIP : nil)
                            let datagram = try codec.makeKeepAliveB(bContext)
                            if !loggedFirstB {
                                loggedFirstB = true
                                emit(.log("保活 B 首包（\(datagram.count) 字节）=\(Hex.string(datagram))"))
                            } else if packetIndex == 1, !loggedFirstC {
                                loggedFirstC = true
                                emit(.log("保活 C 首包（\(datagram.count) 字节）=\(Hex.string(datagram))"))
                            }
                            emit(.log(String(format: "保活B 发送 type=0x%02X counter=0x%02X session=0x%04X tail=0x%08X size=%d%@",
                                             Int(type), Int(bCounter), Int(serverSessionID), Int(tail),
                                             datagram.count, bLegacyTypes ? " [旧格式]" : "")))
                            try await context.channel.send(datagram)
                            bSent += 1
                            let incoming = try await receive(matching: { frame in
                                switch frame {
                                case .keepAliveBRequest, .keepAliveBReply: true
                                default: false
                                }
                            }, timeout: configuration.keepAliveInterval)
                            switch incoming.frame {
                            case .keepAliveBRequest(let replyType, let replyCounter, let replyTail):
                                bAnswered += 1
                                if !loggedFirstBReply {
                                    loggedFirstBReply = true
                                    emit(.log("保活B 应答原文（\(incoming.payload.count) 字节）=\(Hex.string(incoming.payload, limit: 40))"))
                                }
                                emit(.log(String(format: "保活B 应答 type=0x%02X counter=0x%02X tail=0x%08X size=%d",
                                                 Int(replyType), Int(replyCounter), Int(replyTail),
                                                 incoming.payload.count)))
                                tail = replyTail
                            case .keepAliveBReply(let reply):
                                // 272 字节：网关对文件包的确认，**不是** A/C 应答，tail 不取。
                                emit(.log("保活B 文件包应答 \(reply.raw.count) 字节（不参与 tail）"))
                            default:
                                break
                            }
                        }
                        bTimeouts = 0
                    } catch let error as DrcomError where error == .cancelled {
                        throw error
                    } catch {
                        // B 保活收不到回执**不判定掉线**：会话存亡由保活 A（带服务端统计）
                        // 和在线巡检决定。B 失败只记日志，下一轮继续试。
                        bTimeouts += 1
                        if bTimeouts <= 3 || bTimeouts % 10 == 0 {
                            emit(.log("保活B 无应答（累计 \(bTimeouts) 次，不判定掉线；本会话 应答 \(bAnswered)/\(bSent)）"))
                        }
                        if bTimeouts == 3 {
                            emit(.log("保活B 连续 3 轮无应答：网关可能不认这套格式——诊断里请带上上面 type/counter/tail 那几行"))
                        }
                        // 整场一包都没应答 → 换另一种方言试一次（真网关的确切方言无法离线确认）
                        if bAnswered == 0, bProbesLeft > 0 {
                            bProbesLeft -= 1
                            bLegacyTypes.toggle()
                            emit(.log(bLegacyTypes
                                ? "保活B 主格式（01/03）整轮无应答 → 换旧格式（0x05=序号 05/07）再试"
                                : "保活B 旧格式也无应答 → 回到主格式（01/03），停止试探"))
                        } else if bAnswered == 0, bLegacyTypes {
                            // 旧格式也没人应：说明换方言没用（或第一轮只是丢包），回到主格式别再乱换
                            bLegacyTypes = false
                            emit(.log("保活B 旧格式也无应答 → 回到主格式（01/03），停止试探"))
                        }
                        try? await clock.sleep(for: .seconds(1))
                    }
                    // 第一轮 B 结束（不论成败）就给一行自检结论：
                    // 方言不对时不用等十几分钟、看会话掉线才发现。
                    if !bLoggedVerdict, bSent > 0 {
                        bLoggedVerdict = true
                        let verdict = bAnswered == 0
                            ? "全部无应答 ❌"
                            : (bAnswered >= bSent ? "全部应答 ✅" : "\(bAnswered)/\(bSent) 包有应答 ⚠️")
                        emit(.log("保活B 自检：\(verdict)（已发 \(bSent) 包 / 应答 \(bAnswered) 包；type 必须 01/03）"))
                    }
                }
            } catch let error as DrcomError where error == .cancelled {
                throw error
            } catch {
                // 只有保活 A 的失败会走到这里（B 的失败在 B 分支内部就吞掉了）。
                misses += 1
                emit(.log("保活A 超时（第 \(misses) 次，间隔 \(configuration.keepAliveInterval)）"))
                // 先用真实探测确认网络是否真断：网关不回保活应答 ≠ 会话失效
                if misses >= 2, let liveness = configuration.livenessCheck,
                   await liveness(context.interface) {
                    emit(.log("保活无应答但网络实际可达：继续视为在线"))
                    misses = 0
                    try? await clock.sleep(for: configuration.keepAliveInterval)
                    continue
                }
                if misses >= configuration.missTolerance {
                    throw DrcomError.gatewayUnreachable(host: configuration.server.description)
                }
                // 丢一轮也要等一个间隔再发，不能原地空转（否则会把网关打成风暴）
                try? await clock.sleep(for: configuration.keepAliveInterval)
                continue
            }
            do {
                try await clock.sleep(for: configuration.keepAliveInterval)
            } catch {
                throw DrcomError.cancelled
            }
        }
        throw DrcomError.cancelled
    }

    // MARK: 收包

    private struct IncomingFrame: Sendable {
        let frame: DrcomFrame
        let payload: Data
    }

    private func receive(matching predicate: @Sendable (DrcomFrame) -> Bool,
                         timeout: Duration) async throws -> IncomingFrame {
        guard let channel else { throw DrcomError.channelFailure("通道未打开") }
        let deadline = clock.now() + timeout
        while clock.now() < deadline {
            let remaining = deadline - clock.now()
            let datagram = try await channel.receive(timeout: remaining)
            let frame = codec.classify(datagram)
            if case .unknown(let type, let subtype, let length) = frame {
                // 网关有时会发帧表里没有的包（真机见过 type=7 len=272）。
                // 第一次遇到时把前 32 字节记进日志/诊断，下次看诊断就能推断它是什么；
                // 同一种包只记一次，别把日志刷爆。
                let signature = "\(type)/\(subtype)/\(length)"
                if !loggedUnknownSignatures.contains(signature) {
                    loggedUnknownSignatures.insert(signature)
                    let head = datagram.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
                    emit(.log("忽略未知报文 type=\(type) sub=\(subtype) len=\(length) head=\(head)"))
                }
                continue
            }
            if predicate(frame) { return IncomingFrame(frame: frame, payload: datagram) }
        }
        throw DrcomError.timeout(stage: "receive")
    }

    // MARK: 会话计数

    /// challenge 序号：16 位自增。抓包里依次是 1d63 / 2f63 / 3f63，
    /// 服务器只是原样回显，所以取值本身不重要，**单调**才重要。
    private func nextSerial() -> UInt16 {
        if serialCounter == 0 {
            serialCounter = 0x1D63
        } else {
            serialCounter &+= 0x1200
        }
        return serialCounter
    }

    /// 保活里的"会话号"其实是**秒计数**（小端）：登录时取 challenge 序号的小端值，
    /// 之后按登录已过秒数递增（抓包 25373 → 25408 = 35s，正好是两次包的时间差）。
    private func sessionBase(from serial: UInt16) -> UInt16 {
        let high = UInt16(UInt8(truncatingIfNeeded: serial))
        let low = UInt16(UInt8(truncatingIfNeeded: serial >> 8))
        return (high << 8) | low
    }

    private func currentSessionCounter(base: UInt16) -> UInt16 {
        guard let started = sessionStartedAt else { return base }
        let elapsed = clock.now() - started
        let seconds = UInt16(truncatingIfNeeded: max(0, elapsed.components.seconds))
        return base &+ seconds
    }

    private func currentTimestamp() -> UInt32 {
        UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970))
    }

    // MARK: 状态与生命周期

    private func nextEpoch() -> UInt64 {
        epoch &+= 1
        return epoch
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        epoch == value
    }

    private func setState(_ next: AuthState) {
        guard next != state else { return }
        if !state.canTransition(to: next) {
            emit(.log("非法状态转移 \(state.phase) → \(next.phase)（已阻止）"))
            return
        }
        state = next
        emit(.state(next))
    }

    private func emit(_ event: Event) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func teardown() async {
        if let channel {
            await channel.close()
        }
        channel = nil
        sessionStartedAt = nil
    }
}
