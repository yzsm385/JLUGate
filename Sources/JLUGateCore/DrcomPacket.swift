import Foundation

/// 随机源抽象：未知区字段要随机，但黄金测试必须逐字节可复现。
public protocol RandomSource: Sendable {
    func bytes(count: Int) -> [UInt8]
}

public struct SystemRandomSource: RandomSource {
    public init() {}
    public func bytes(count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }
}

/// 确定性随机（SplitMix64），单测用。
public struct SeededRandomSource: RandomSource {
    private let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public func bytes(count: Int) -> [UInt8] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        var output: [UInt8] = []
        output.reserveCapacity(count)
        while output.count < count {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            for shift in stride(from: 0, to: 64, by: 8) where output.count < count {
                output.append(UInt8(truncatingIfNeeded: z >> UInt64(shift)))
            }
        }
        return output
    }
}

/// 固定随机源：把夹具里的"未知区"原样喂回去，用于整包逐字节比对。
public struct FixedRandomSource: RandomSource {
    private let pool: [UInt8]
    private let fallback: any RandomSource

    public init(pool: [UInt8], fallback: any RandomSource = SystemRandomSource()) {
        self.pool = pool
        self.fallback = fallback
    }

    public func bytes(count: Int) -> [UInt8] {
        guard pool.count >= count else { return fallback.bytes(count: count) }
        return Array(pool.prefix(count))
    }
}

// MARK: - Challenge

public struct ChallengeReply: Sendable, Equatable {
    public var serial: UInt16
    public var subtype: UInt8
    public var salt: [UInt8]
    public var serverReportedClientIP: IPv4Address?
    /// 服务器分配的会话别名（保活 B 用）。
    public var sessionID: UInt16
    public var raw: [UInt8]

    public init(serial: UInt16, subtype: UInt8, salt: [UInt8],
                serverReportedClientIP: IPv4Address?, sessionID: UInt16 = 0, raw: [UInt8]) {
        self.serial = serial
        self.subtype = subtype
        self.salt = salt
        self.serverReportedClientIP = serverReportedClientIP
        self.sessionID = sessionID
        self.raw = raw
    }
}

// MARK: - 登录

public struct LoginContext: Sendable {
    public var account: String
    public var password: String
    public var salt: [UInt8]
    public var clientIP: IPv4Address
    public var linkLocalIP: IPv4Address?
    public var hostname: String
    public var mac: MACAddress
    /// 覆盖未知区（测试用）。为 nil 时按 `PacketLayout` 填随机值。
    public var nonceOverrides: NonceOverrides

    public init(account: String, password: String, salt: [UInt8],
                clientIP: IPv4Address, linkLocalIP: IPv4Address? = nil,
                hostname: String, mac: MACAddress, nonceOverrides: NonceOverrides = .init()) {
        self.account = account
        self.password = password
        self.salt = salt
        self.clientIP = clientIP
        self.linkLocalIP = linkLocalIP
        self.hostname = hostname
        self.mac = mac
        self.nonceOverrides = nonceOverrides
    }
}

/// 未知区的显式取值（黄金测试 / "复制抓包常量重试"策略用）。
public struct NonceOverrides: Sendable, Equatable {
    public var nonce22: [UInt8]?
    public var nonce8: [UInt8]?
    public var nonce10: [UInt8]?
    public var nonce4: [UInt8]?
    public var nonce2: [UInt8]?

    public init(nonce22: [UInt8]? = nil, nonce8: [UInt8]? = nil, nonce10: [UInt8]? = nil,
                nonce4: [UInt8]? = nil, nonce2: [UInt8]? = nil) {
        self.nonce22 = nonce22
        self.nonce8 = nonce8
        self.nonce10 = nonce10
        self.nonce4 = nonce4
        self.nonce2 = nonce2
    }

    public static let empty = NonceOverrides()
}

public struct SessionTicket: Sendable, Equatable {
    public var account: String
    public var clientIP: IPv4Address
    /// 登录摘要 A：保活 A 请求的 0x01–0x10 就是它（实测，见 `KeepAliveA.digestOffset`）。
    public var digestA: [UInt8]
    /// 会话号（大端 2 字节），保活 A 请求 0x24 与应答 0x06 回显同一个值。
    public var session: UInt16
    /// `Drco` 块里的两个不透明 2 字节，登录成功后由服务器下发，保活要带回去。
    public var opaque1: UInt16
    public var opaque2: UInt16
    /// 登录成功包里的计费/区间原始值（小端 u32 ×2），语义未解，仅记录。
    public var loginQuota: [UInt32]
    public var raw: [UInt8]

    public init(account: String, clientIP: IPv4Address, digestA: [UInt8], session: UInt16,
                opaque1: UInt16, opaque2: UInt16, loginQuota: [UInt32], raw: [UInt8]) {
        self.account = account
        self.clientIP = clientIP
        self.digestA = digestA
        self.session = session
        self.opaque1 = opaque1
        self.opaque2 = opaque2
        self.loginQuota = loginQuota
        self.raw = raw
    }
}

// MARK: - 保活

public enum KeepAliveKind: String, Sendable, CaseIterable {
    /// 38 字节请求 → 72 字节应答（`FF` → `07 01 10 00`）
    case a
    /// 40 字节请求 → 40 字节应答（`07 <round> 28 00 0B`）
    case b
}

public struct KeepAliveAStatus: Sendable, Equatable {
    public var session: UInt16
    /// 0x1C 起 6 个小端 u32；`stats[1]` 实测随秒递增（本次在线秒数）。
    public var stats: [UInt32]
    public var secondsOnline: UInt32
    public var raw: [UInt8]
}

public struct KeepAliveBContext: Sendable, Equatable {
    public var round: UInt8
    public var seq: UInt8
    public var session: UInt16
    public var timestamp: UInt32
    public var mirror: UInt32
    public var check: UInt32
    /// 一对里的第 2 包装客户端 IP，第 1 包留 0。
    public var clientIP: IPv4Address?

    public init(round: UInt8, seq: UInt8, session: UInt16, timestamp: UInt32,
                mirror: UInt32, check: UInt32, clientIP: IPv4Address? = nil) {
        self.round = round
        self.seq = seq
        self.session = session
        self.timestamp = timestamp
        self.mirror = mirror
        self.check = check
        self.clientIP = clientIP
    }
}

public struct KeepAliveBReply: Sendable, Equatable {
    public var round: UInt8
    public var seq: UInt8
    public var session: UInt16
    public var mirror: UInt32
    public var raw: [UInt8]
}

// MARK: - 帧分类

/// 按 `(type, subtype, length)` 三元组识别（CHECKLIST §2 / PLAN §5.2）。
public enum DrcomFrame: Sendable, Equatable {
    case challenge(serial: UInt16)
    case challengeReply(ChallengeReply)
    case accountProbe
    case genericAck
    case login(after: UInt16?)
    case loginSuccess(SessionTicket)
    case loginFailure(reason: String)
    case keepAliveARequest
    case keepAliveAReply(KeepAliveAStatus)
    case keepAliveBRequest(seq: UInt8, round: UInt8)
    case keepAliveBReply(KeepAliveBReply)
    case unknown(type: UInt8, subtype: UInt8, length: Int)

    public var type: UInt8 {
        switch self {
        case .challenge: PacketLayout.Challenge.kind
        case .challengeReply: PacketLayout.ChallengeReply.kind
        case .accountProbe: 0x06
        case .genericAck: PacketLayout.LoginResult.successKind
        case .login: PacketLayout.Login.kind
        case .loginSuccess: PacketLayout.LoginResult.successKind
        case .loginFailure: PacketLayout.LoginResult.failureKind
        case .keepAliveARequest: PacketLayout.KeepAliveA.kind
        case .keepAliveAReply: PacketLayout.KeepAliveA.replyKind
        case .keepAliveBRequest, .keepAliveBReply: PacketLayout.KeepAliveB.kind
        case .unknown(let type, _, _): type
        }
    }
}
