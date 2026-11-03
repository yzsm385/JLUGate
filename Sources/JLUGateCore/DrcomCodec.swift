import Foundation

/// 编解码契约（PLAN §4 的签名即契约）。
public protocol DrcomCodecProtocol: Sendable {
    func makeChallenge(serial: UInt16, subtype: UInt8) throws -> Data
    func parseChallengeReply(_ data: Data) throws -> ChallengeReply
    func makeLogin(_ context: LoginContext) throws -> Data
    func parseLoginReply(_ data: Data) throws -> SessionTicket
    func makeKeepAliveA(ticket: SessionTicket, server: IPv4Address) throws -> Data
    func parseKeepAliveAReply(_ data: Data) throws -> KeepAliveAStatus
    func makeKeepAliveB(_ context: KeepAliveBContext) throws -> Data
    func parseKeepAliveBReply(_ data: Data) throws -> KeepAliveBReply
}

public struct DrcomCodec: DrcomCodecProtocol, Sendable {
    public var randomness: any RandomSource

    public init(randomness: any RandomSource = SystemRandomSource()) {
        self.randomness = randomness
    }

    // MARK: 摘要

    /// `MD5(0x03 ‖ 0x01 ‖ salt ‖ password_utf8)`。中间明文 buffer 用完即清零。
    public static func digestA(password: String, salt: [UInt8]) -> [UInt8] {
        var buffer = PacketLayout.digestPrefix
        buffer.append(contentsOf: salt)
        buffer.append(contentsOf: Array(password.utf8))
        defer {
            for index in buffer.indices { buffer[index] = 0 }
        }
        return MD5.hash(buffer)
    }

    // MARK: Challenge

    public func makeChallenge(serial: UInt16, subtype: UInt8 = PacketLayout.Challenge.firstSubtype) throws -> Data {
        var writer = ByteWriter(count: PacketLayout.Length.challenge)
        try writer.put(PacketLayout.Challenge.kind, at: 0x00)
        try writer.put(subtype, at: PacketLayout.Challenge.subtypeOffset)
        try writer.put(serial, at: PacketLayout.Challenge.serialOffset, endian: .big)
        try writer.put(PacketLayout.Challenge.flag, at: PacketLayout.Challenge.flagOffset)
        return writer.data()
    }

    public func parseChallengeReply(_ data: Data) throws -> ChallengeReply {
        guard data.count == PacketLayout.Length.challengeReply else {
            throw DrcomError.unexpectedPacket(
                type: data.count > 0 ? data[data.startIndex] : 0,
                subtype: data.count > 1 ? data[data.startIndex + 1] : 0,
                length: data.count)
        }
        let reader = ByteReader(data)
        let kind = try reader.u8(at: 0)
        guard kind == PacketLayout.ChallengeReply.kind else {
            throw DrcomError.unexpectedPacket(type: kind, subtype: try reader.u8(at: 1), length: data.count)
        }
        let salt = try reader.slice(PacketLayout.ChallengeReply.saltOffset,
                                    PacketLayout.ChallengeReply.saltLength)
        let ipBytes = try reader.slice(PacketLayout.ChallengeReply.clientIPOffset,
                                       PacketLayout.ChallengeReply.clientIPLength)
        return ChallengeReply(
            serial: try reader.u16(at: PacketLayout.ChallengeReply.serialOffset, endian: .big),
            subtype: try reader.u8(at: 1),
            salt: salt,
            serverReportedClientIP: IPv4Address(bytes: ipBytes),
            sessionID: try reader.u16(at: PacketLayout.ChallengeReply.sessionIDOffset, endian: .little),
            raw: Array(data))
    }

    // MARK: 登录包

    public func makeLogin(_ context: LoginContext) throws -> Data {
        let length = PacketLayout.Length.login
        var writer = ByteWriter(count: length)
        let L = PacketLayout.Login.self

        try writer.put(L.kind, at: 0x000)
        try writer.put(L.subtype, at: 0x001)
        try writer.put(L.magicValue, at: L.magicOffset, endian: .big)

        let digest = Self.digestA(password: context.password, salt: context.salt)
        try writer.put(digest, at: L.digestAOffset)
        try writer.putCString(context.account, at: L.accountOffset, length: L.accountLength)

        try writer.put(nonce(length: L.nonce22Length, override: context.nonceOverrides.nonce22),
                       at: L.nonce22Offset)
        try writer.put(L.addressFamilyValue, at: L.addressFamilyOffset)
        try writer.put(context.clientIP.bytes, at: L.clientIPOffset)
        try writer.put(context.linkLocalIP?.bytes ?? [0, 0, 0, 0], at: L.linkLocalIPOffset)
        try writer.put(nonce(length: L.nonce8Length, override: context.nonceOverrides.nonce8),
                       at: L.nonce8Offset)
        try writer.put(L.flag1Value, at: L.flag1Offset)
        try writer.putCString(context.hostname, at: L.hostnameOffset, length: L.hostnameLength)
        try writer.put(L.flag2Value, at: L.flag2Offset)
        try writer.put(PacketLayout.loginMagic, at: L.magicOffset2)
        try writer.put(L.fixed0BB, at: L.fixed0BBOffset)
        try writer.putCString(PacketLayout.clientVersion, at: L.versionOffset, length: L.versionLength)
        try writer.putCString(PacketLayout.staticToken, at: L.tokenOffset, length: L.tokenLength)
        try writer.put(L.fixed136, at: L.fixed136Offset)
        try writer.put(nonce(length: L.nonce10Length, override: context.nonceOverrides.nonce10),
                       at: L.nonce10Offset)
        try writer.put(L.fixed144, at: L.fixed144Offset)
        try writer.put(nonce(length: L.nonce4Length, override: context.nonceOverrides.nonce4),
                       at: L.nonce4Offset)
        try writer.put(context.mac.bytes, at: L.macOffset)
        try writer.put(nonce(length: L.nonce2Length, override: context.nonceOverrides.nonce2),
                       at: L.nonce2Offset)
        return writer.data()
    }

    /// 失败原因：0x18 起、NUL 结尾，**原样**返回（`ldap auth error`…）。
    public func parseLoginFailureReason(_ data: Data) throws -> String {
        guard data.count >= PacketLayout.Length.loginFailure else {
            throw DrcomError.malformed("失败包长度应为 \(PacketLayout.Length.loginFailure)，实际 \(data.count)")
        }
        let reader = ByteReader(data)
        return try reader.cString(PacketLayout.LoginResult.failureReasonOffset,
                                  data.count - PacketLayout.LoginResult.failureReasonOffset)
    }

    public func parseLoginReply(_ data: Data) throws -> SessionTicket {
        let reader = ByteReader(data)
        let type = try reader.u8(at: 0)
        guard type == PacketLayout.LoginResult.successKind,
              data.count == PacketLayout.Length.loginSuccess else {
            if type == PacketLayout.LoginResult.failureKind {
                throw DrcomError.classifyRejection(try parseLoginFailureReason(data))
            }
            throw DrcomError.unexpectedPacket(
                type: type,
                subtype: try reader.u8(at: 1),
                length: data.count)
        }

        let base = PacketLayout.LoginResult.successTailOffset
        let block = PacketLayout.DrcoBlock.self
        let magic = try reader.slice(base + block.magicOffset, block.magicLength)
        guard magic == PacketLayout.keepAliveMagic else {
            throw DrcomError.malformed("登录成功包缺少 Drco 块")
        }
        let serverIP = IPv4Address(bytes: try reader.slice(base + block.serverIPOffset, 4))
        let clientIP = IPv4Address(bytes: try reader.slice(base + block.clientIPOffset, 4))
        _ = serverIP

        return SessionTicket(
            account: "",
            clientIP: clientIP ?? .zero,
            digestA: [],
            session: 0,
            opaque1: try reader.u16(at: base + block.opaque1Offset, endian: .big),
            opaque2: try reader.u16(at: base + block.opaque2Offset, endian: .big),
            loginQuota: [
                try reader.u32(at: 0x05, endian: .little),
                try reader.u32(at: 0x09, endian: .little),
            ],
            raw: Array(data))
    }

    // MARK: 保活 A

    public func makeKeepAliveA(ticket: SessionTicket, server: IPv4Address) throws -> Data {
        var writer = ByteWriter(count: PacketLayout.Length.keepAliveARequest)
        let A = PacketLayout.KeepAliveA.self
        let block = PacketLayout.DrcoBlock.self
        let base = A.drcoBlockOffset

        try writer.put(A.kind, at: 0x00)
        guard ticket.digestA.count == A.digestLength else {
            throw DrcomError.malformed("保活 A 需要 16 字节登录摘要，实际 \(ticket.digestA.count)")
        }
        try writer.put(ticket.digestA, at: A.digestOffset)
        try writer.put(PacketLayout.keepAliveMagic, at: base + block.magicOffset)
        try writer.put(server.bytes, at: base + block.serverIPOffset)
        try writer.put(ticket.opaque1, at: base + block.opaque1Offset, endian: .big)
        try writer.put(ticket.clientIP.bytes, at: base + block.clientIPOffset)
        try writer.put(ticket.opaque2, at: base + block.opaque2Offset, endian: .big)
        try writer.put(ticket.session, at: A.sessionOffset, endian: .little)
        return writer.data()
    }

    public func parseKeepAliveAReply(_ data: Data) throws -> KeepAliveAStatus {
        guard data.count == PacketLayout.Length.keepAliveAReply else {
            throw DrcomError.unexpectedPacket(
                type: data.count > 0 ? data[data.startIndex] : 0,
                subtype: data.count > 1 ? data[data.startIndex + 1] : 0,
                length: data.count)
        }
        let reader = ByteReader(data)
        let A = PacketLayout.KeepAliveA.self
        var stats: [UInt32] = []
        for index in 0..<A.statsCount {
            stats.append(try reader.u32(at: A.statsOffset + index * 4, endian: .little))
        }
        return KeepAliveAStatus(
            session: try reader.u16(at: A.replySessionOffset, endian: .little),
            stats: stats,
            secondsOnline: stats.dropFirst().first ?? 0,
            raw: Array(data))
    }

    // MARK: 保活 B

    public func makeKeepAliveB(_ context: KeepAliveBContext) throws -> Data {
        var writer = ByteWriter(count: PacketLayout.Length.keepAliveB)
        let B = PacketLayout.KeepAliveB.self
        try writer.put(B.kind, at: 0x00)
        try writer.put(context.round, at: B.roundOffset)
        try writer.put(B.lengthFieldValue, at: B.lengthFieldOffset, endian: .little)
        try writer.put(B.flagValue, at: B.flagOffset)
        try writer.put(context.seq, at: B.seqOffset)
        try writer.put(context.session, at: B.sessionOffset, endian: .little)
        try writer.put(context.timestamp, at: B.timestampOffset, endian: .little)
        try writer.put(context.mirror, at: B.mirrorOffset, endian: .little)
        try writer.put(context.check, at: B.checkOffset, endian: .little)
        if let ip = context.clientIP {
            try writer.put(ip.bytes, at: B.clientIPOffset)
        }
        return writer.data()
    }

    public func parseKeepAliveBReply(_ data: Data) throws -> KeepAliveBReply {
        guard data.count == PacketLayout.Length.keepAliveB else {
            throw DrcomError.unexpectedPacket(
                type: data.count > 0 ? data[data.startIndex] : 0,
                subtype: data.count > 1 ? data[data.startIndex + 1] : 0,
                length: data.count)
        }
        let reader = ByteReader(data)
        let B = PacketLayout.KeepAliveB.self
        return KeepAliveBReply(
            round: try reader.u8(at: B.roundOffset),
            seq: try reader.u8(at: B.seqOffset),
            session: try reader.u16(at: B.sessionOffset, endian: .little),
            mirror: try reader.u32(at: B.mirrorOffset, endian: .little),
            raw: Array(data))
    }

    // MARK: 分类

    public func classify(_ data: Data) -> DrcomFrame {
        guard let type = data.first else {
            return .unknown(type: 0, subtype: 0, length: 0)
        }
        let subtype = data.count > 1 ? data[data.startIndex + 1] : 0
        let length = data.count
        let reader = ByteReader(data)

        switch (type, length) {
        case (PacketLayout.Challenge.kind, PacketLayout.Length.challenge):
            let serial = (try? reader.u16(at: PacketLayout.Challenge.serialOffset, endian: .big)) ?? 0
            return .challenge(serial: serial)
        case (PacketLayout.ChallengeReply.kind, PacketLayout.Length.challengeReply):
            if let reply = try? parseChallengeReply(data) { return .challengeReply(reply) }
        case (0x06, PacketLayout.Length.accountProbe):
            return .accountProbe
        case (PacketLayout.LoginResult.successKind, PacketLayout.Length.genericAck):
            return .genericAck
        case (PacketLayout.Login.kind, PacketLayout.Length.login):
            return .login(after: nil)
        case (PacketLayout.LoginResult.successKind, PacketLayout.Length.loginSuccess):
            if let ticket = try? parseLoginReply(data) { return .loginSuccess(ticket) }
        case (PacketLayout.LoginResult.failureKind, PacketLayout.Length.loginFailure):
            let reason = (try? parseLoginFailureReason(data)) ?? ""
            return .loginFailure(reason: reason)
        case (PacketLayout.KeepAliveA.kind, PacketLayout.Length.keepAliveARequest):
            return .keepAliveARequest
        case (PacketLayout.KeepAliveA.replyKind, PacketLayout.Length.keepAliveAReply):
            if let status = try? parseKeepAliveAReply(data) { return .keepAliveAReply(status) }
        case (PacketLayout.KeepAliveB.kind, PacketLayout.Length.keepAliveB):
            let seq = (try? reader.u8(at: PacketLayout.KeepAliveB.seqOffset)) ?? 0
            let round = (try? reader.u8(at: PacketLayout.KeepAliveB.roundOffset)) ?? 0
            // 请求与应答同为 40 字节，只能靠"是否是本端刚发出的序号"区分，
            // 因此这里保守地统一按 B 型报文返回，由引擎按上下文判断。
            return .keepAliveBRequest(seq: seq, round: round)
        default:
            break
        }
        return .unknown(type: type, subtype: subtype, length: length)
    }

    // MARK: 工具

    private func nonce(length: Int, override: [UInt8]?) -> [UInt8] {
        if let override, override.count == length { return override }
        return randomness.bytes(count: length)
    }
}
