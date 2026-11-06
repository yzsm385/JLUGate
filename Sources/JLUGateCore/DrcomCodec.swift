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
        try makeLogin(context, variant: .current)
    }

    /// 指定版本（引擎在服务端回 0x15 时换版本重试）。
    public func makeLogin(_ context: LoginContext,
                          variant: LoginVariant) throws -> Data {
        variant == .current ? try makeCurrentLogin(context) : try makeLegacyLogin(context)
    }

    private func makeCurrentLogin(_ context: LoginContext) throws -> Data {
        let L = PacketLayout.Login.self
        let account = Array(context.account.utf8)
        let password = Array(context.password.utf8)
        let pad = L.padding(passwordLength: password.count)
        let length = L.length(passwordLength: password.count)

        var data = [UInt8](repeating: 0, count: length)
        data[0] = L.kind
        data[1] = L.subtype
        data[2] = 0x00
        data[3] = UInt8(truncatingIfNeeded: account.count + 20)

        let md5a = Self.digestA(password: context.password, salt: context.salt)
        write(md5a, into: &data, at: L.digestAOffset)
        write(Array(account.prefix(L.accountLength)), into: &data, at: L.accountOffset)

        data[L.controlOffset] = 0x20
        data[L.adapterOffset] = 0x03
        let mac = context.mac.bytes
        for index in 0..<L.xorLength { data[L.xorOffset + index] = md5a[index] ^ mac[index] }

        var md5bInput: [UInt8] = [0x01]
        md5bInput += password
        md5bInput += context.salt
        md5bInput += [0, 0, 0, 0]
        write(MD5.hash(md5bInput), into: &data, at: L.md5bOffset)

        data[L.ipCountOffset] = 0x01

        // 注意：输入是"前 97 字节 + 4 字节探针"共 101 字节
        write(L.md5cProbe, into: &data, at: L.md5cOffset)
        write(Array(MD5.hash(Array(data[0..<101]))[0..<L.md5cLength]), into: &data, at: L.md5cOffset)
        data[L.ipDogOffset] = 0x01

        write(Array(L.vendor.utf8), into: &data, at: L.vendorOffset)
        write(L.dnsValue, into: &data, at: L.dnsOffset)

        for field in L.osFields {
            let value = field.value
            write([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                   UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)],
                  into: &data, at: field.offset)
        }
        write(L.hostBlob, into: &data, at: L.hostBlobOffset)
        write(Array(L.servicePack.utf8), into: &data, at: L.servicePackOffset)

        data[L.tailMarkerOffset] = L.tailMarker
        data[L.passwordLengthOffset] = UInt8(truncatingIfNeeded: password.count)

        var counter = L.passwordSectionOffset + 2
        for index in 0..<password.count {
            let mixed = md5a[index % md5a.count] ^ password[index]
            data[counter + index] = (mixed << 3) &+ (mixed >> 5)
        }
        counter += password.count
        write(L.separatorAfterROR, into: &data, at: counter)

        let checksum = Self.loginChecksum(Array(data[0..<(counter + 2)]), mac: mac)
        write(checksum, into: &data, at: counter + 2)
        write(Array(mac[0..<6]), into: &data, at: counter + L.macOffsetAfterROR)

        write(L.tailFoot, into: &data, at: counter + pad.rorPadding + 14)
        return Data(data)
    }

    /// 旧版（2026-11-02 抓包实测）布局：基础长度 334 + (p-1)/4*4。
    private func makeLegacyLogin(_ context: LoginContext) throws -> Data {
        let account = Array(context.account.utf8)
        let password = Array(context.password.utf8)
        let p = min(max(password.count, 1), 16)
        let length = 334 + (p - 1) / 4 * 4
        var data = [UInt8](repeating: 0, count: length)

        data[0] = 0x03; data[1] = 0x01; data[2] = 0x00
        data[3] = UInt8(truncatingIfNeeded: account.count + 20)
        let md5a = Self.digestA(password: context.password, salt: context.salt)
        write(md5a, into: &data, at: 0x04)
        write(Array(account.prefix(36)), into: &data, at: 0x14)
        let mac = context.mac.bytes
        for i in 0..<6 { data[0x3A + i] = md5a[i] ^ mac[i] }

        var md5bInput: [UInt8] = [0x01]
        md5bInput += password; md5bInput += context.salt; md5bInput += [0, 0, 0, 0]
        write(MD5.hash(md5bInput), into: &data, at: 0x40)

        let hasLinkLocal = context.linkLocalIP != nil
        data[0x50] = hasLinkLocal ? 0x02 : 0x01
        write(context.clientIP.bytes, into: &data, at: 0x51)
        if let linkLocal = context.linkLocalIP { write(linkLocal.bytes, into: &data, at: 0x55) }

        write([0x14, 0x00, 0x07, 0x0B], into: &data, at: 0x61)
        write(Array(MD5.hash(Array(data[0..<101]))[0..<8]), into: &data, at: 0x61)
        data[0x69] = 0x01
        write(Array(context.hostname.utf8.prefix(32)), into: &data, at: 0x6E)
        write([10, 10, 10, 10], into: &data, at: 0x8E)

        // 旧版固定模板（两帧抓包完全一致）
        let template: [UInt8] = [
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0x02, 0x44, 0x72, 0x43, 0x4F, 0x4D, 0x00, 0xCF, 0x07, 0x31, 0x00,
            0x32, 0x35, 0x2E, 0x36, 0x2E, 0x30,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        ]
        write(template, into: &data, at: 0x9A)
        write(Array("56c68373463f4cd5b73dd3ac5e3673000a5fdd7e".utf8), into: &data, at: 0xF6)
        // 0x136 起是 "31 00 00 <密码长度>"（不是 0x6a 标记）
        write([0x31, 0x00, 0x00, UInt8(truncatingIfNeeded: p)], into: &data, at: 0x136)
        for i in 0..<password.count {
            let mixed = md5a[i % md5a.count] ^ password[i]
            data[314 + i] = (mixed << 3) &+ (mixed >> 5)
        }
        let afterROR = 314 + password.count
        write([0x02, 0x0C], into: &data, at: afterROR)

        let macBase = 322 + password.count
        write([0x01, 0x26, 0x07, 0x11, 0x00, 0x00], into: &data, at: afterROR + 2)
        write(Array(mac[0..<6]), into: &data, at: macBase)
        let zero = (4 - p % 4) % 4
        // 旧版：直接对"已写好的前缀（含占位与 MAC）"做小端异或折叠
        let checksum = Self.checksumLE(Array(data[0..<(328 + password.count + zero)]))
        write(checksum, into: &data, at: afterROR + 2)
        let randomOffset = 328 + password.count + zero
        let override = context.nonceOverrides.nonce2 ?? []
        data[randomOffset] = override.first ?? UInt8.random(in: 0...255)
        data[randomOffset + 1] = override.count > 1 ? override[1] : UInt8.random(in: 0...255)
        return Data(data)
    }

    /// 纯异或折叠校验：每 4 字节小端读成 UInt32 累异或，乘 1968 取低 32 位，小端写出。
    static func checksumLE(_ bytes: [UInt8]) -> [UInt8] {
        var acc: UInt32 = 1234
        var index = 0
        while index + 4 <= bytes.count {
            acc ^= UInt32(bytes[index])
                | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16
                | UInt32(bytes[index + 3]) << 24
            index += 4
        }
        if index < bytes.count {
            var tail: UInt32 = 0
            for offset in 0..<(bytes.count - index) {
                tail |= UInt32(bytes[index + offset]) << (8 * offset)
            }
            acc ^= tail
        }
        let result = (acc &* 1968) & 0xFFFF_FFFF
        return [UInt8(result & 0xFF), UInt8((result >> 8) & 0xFF),
                UInt8((result >> 16) & 0xFF), UInt8((result >> 24) & 0xFF)]
    }

    /// 登录包尾部的异或折叠校验（初值 1234，乘 1968，小端写出）。
    static func loginChecksum(_ prefix: [UInt8], mac: [UInt8]) -> [UInt8] {
        var buffer = prefix
        buffer += [0x01, 0x26, 0x07, 0x11, 0x00, 0x00]
        buffer += Array(mac.prefix(6))
        var acc: UInt32 = 1234
        var index = 0
        while index + 4 <= buffer.count {
            acc ^= UInt32(buffer[index])
                | UInt32(buffer[index + 1]) << 8
                | UInt32(buffer[index + 2]) << 16
                | UInt32(buffer[index + 3]) << 24
            index += 4
        }
        if index < buffer.count {
            var tail: UInt32 = 0
            for offset in 0..<(buffer.count - index) {
                tail |= UInt32(buffer[index + offset]) << (8 * offset)
            }
            acc ^= tail
        }
        let result = (acc &* 1968) & 0xFFFF_FFFF
        return [UInt8(result & 0xFF), UInt8((result >> 8) & 0xFF),
                UInt8((result >> 16) & 0xFF), UInt8((result >> 24) & 0xFF)]
    }

    private func write(_ bytes: [UInt8], into data: inout [UInt8], at offset: Int) {
        guard offset >= 0, offset + bytes.count <= data.count else { return }
        data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    /// 失败包的错误码（第 4 字节）：0x15 = 需要升级客户端 等。
    public func parseLoginFailureCode(_ data: Data) -> UInt8? {
        guard data.count > 4, data[data.startIndex] == PacketLayout.LoginResult.failureKind else {
            return nil
        }
        return data[data.startIndex + 4]
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
        case (PacketLayout.KeepAliveB.kind, let length) where length > PacketLayout.Length.keepAliveB:
            // 实测吉林大学网关回的保活应答是 272 字节（不是抓包里的 40 字节）：
            // 类型 7、子类型 6，前面 40 字节的结构和请求一样。以前当"未知报文"丢掉，
            // 引擎就一直以为保活 B 没人应答。
            let seq = (try? reader.u8(at: PacketLayout.KeepAliveB.seqOffset)) ?? 0
            let round = (try? reader.u8(at: PacketLayout.KeepAliveB.roundOffset)) ?? 0
            let session = (try? reader.u16(at: PacketLayout.KeepAliveB.sessionOffset, endian: .little)) ?? 0
            let mirror = (try? reader.u32(at: PacketLayout.KeepAliveB.mirrorOffset, endian: .little)) ?? 0
            return .keepAliveBReply(KeepAliveBReply(round: round, seq: seq,
                                                    session: session, mirror: mirror,
                                                    raw: Array(data)))
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
