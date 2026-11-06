import Foundation
import Testing
@testable import JLUGateCore

@Suite("Challenge 与登录应答（真实抓包）")
struct ChallengeGoldenTests {

    @Test("20 字节 challenge 与抓包逐字节一致")
    func challengeBytes() throws {
        let codec = DrcomCodec()
        let cases: [(serial: UInt16, subtype: UInt8, hex: String)] = [
            (0x1D63, 0x03, "01031d6331000000000000000000000000000000"),
            (0x2F63, 0x04, "01042f6331000000000000000000000000000000"),
            (0x3F63, 0x05, "01053f6331000000000000000000000000000000"),
        ]
        for item in cases {
            let produced = [UInt8](try codec.makeChallenge(serial: item.serial, subtype: item.subtype))
            #expect(hexString(produced) == item.hex)
        }
    }

    @Test("三次应答的 salt 各不相同，且必须取紧邻本次登录的那一次")
    func saltExtraction() throws {
        let session = try Fixtures.session()
        let replies = session.all("s2c", length: 76)
        #expect(replies.count == 3)
        let codec = DrcomCodec()
        let salts = try replies.map { try codec.parseChallengeReply(Data($0)).salt }
        #expect(salts.map(hexString) == ["14cb720f", "49cb720f", "6ecb720f"])

        let second = try codec.parseChallengeReply(Data(replies[1]))
        #expect(second.serial == 0x2F63)
        #expect(second.subtype == 0x04)
        #expect(second.serverReportedClientIP?.description == "192.0.2.10")

        // 用错 salt（14cb720f / 6ecb720f）算出来的摘要必须都不是夹具里的那个
        let right = DrcomCodec.digestA(password: "test-pass-2024", salt: salts[1])
        #expect(hexString(right) == "d030ec3cfa269619e0d3c3224b3e9aa6")
        for wrongIndex in [0, 2] {
            let wrong = DrcomCodec.digestA(password: "test-pass-2024", salt: salts[wrongIndex])
            #expect(wrong != right && wrong != right, "取错 salt 必须得到不同摘要")
        }
    }

    @Test("只有真正的 challenge 应答能解析；长度不对必须报错而不是静默")
    func rejectsWrongLength() throws {
        let codec = DrcomCodec()
        #expect(throws: DrcomError.self) {
            _ = try codec.parseChallengeReply(Data(repeating: 0x02, count: 75))
        }
    }

    @Test("37 字节失败包：原因串原样保留，不做翻译")
    func failureReason() throws {
        let session = try Fixtures.session()
        guard let failure = session.first("s2c", length: 37) else {
            Issue.record("夹具里没有 37 字节失败包")
            return
        }
        let codec = DrcomCodec()
        #expect(try codec.parseLoginFailureReason(Data(failure)) == "ldap auth error")
        #expect(throws: DrcomError.self) {
            _ = try codec.parseLoginReply(Data(failure))
        }
        do {
            _ = try codec.parseLoginReply(Data(failure))
        } catch let error as DrcomError {
            #expect(error == .rejected(reason: "ldap auth error"))
            #expect(error.userMessage == "ldap auth error", "必须原样展示服务器串")
            #expect(error.isRetryable == false, "认证失败不许自动重试")
        }
    }

    @Test("45 字节成功包：Drco 块里的两个不透明字段要取出来")
    func successParse() throws {
        let session = try Fixtures.session()
        guard let success = session.first("s2c", length: 45) else {
            Issue.record("夹具里没有 45 字节成功包")
            return
        }
        let codec = DrcomCodec()
        let ticket = try codec.parseLoginReply(Data(success))
        #expect(ticket.clientIP.description == "192.0.2.10")
        #expect(ticket.opaque1 == 0xE687)
        #expect(ticket.opaque2 == 0x0145)
        #expect(ticket.loginQuota == [1241, 653490])
        #expect(ticket.raw == success)
    }
}

@Suite("保活（38→72 与 40→40）")
struct KeepAliveGoldenTests {

    private func ticketFromCapture() throws -> SessionTicket {
        let session = try Fixtures.session()
        let logins = session.all("c2s", length: 342)
        let successes = session.all("s2c", length: 45)
        guard logins.count == 2, let success = successes.first else {
            throw Fixtures.FixtureError.badJSON
        }
        let parsed = try DrcomCodec().parseLoginReply(Data(success))
        // 摘要 A 与会话号来自登录包/握手，不在成功包里，由引擎补上
        return SessionTicket(
            account: session.account,
            clientIP: parsed.clientIP,
            digestA: Array(logins[1][0x004..<0x014]),
            session: 0x63A3,
            opaque1: parsed.opaque1,
            opaque2: parsed.opaque2,
            loginQuota: parsed.loginQuota,
            raw: parsed.raw)
    }

    @Test("保活 A 请求：0x01–0x10 就是登录摘要 A（抓包证明，不再「未解」）")
    func keepAliveARequest() throws {
        let session = try Fixtures.session()
        let captured = session.all("c2s", length: 38)
        #expect(captured.count >= 2)
        guard let expected = captured.last else { return }
        let ticket = try ticketFromCapture()
        let produced = [UInt8](try DrcomCodec().makeKeepAliveA(
            ticket: ticket, server: IPv4Address("10.100.61.3")!))
        #expect(hexString(produced) == hexString(expected))
        #expect(Array(produced[0x01..<0x11]) == Array(expected[0x01..<0x11]))
        #expect(Array(produced[0x14..<0x18]) == Array("Drco".utf8))
        #expect(Array(produced[0x18..<0x1C]) == [10, 100, 61, 3])
        #expect(Array(produced[0x1E..<0x22]) == [192, 0, 2, 10])
        #expect(Array(produced[0x24..<0x26]) == [0xA3, 0x63])
    }

    @Test("保活 A 应答：会话号回显 + 统计量按小端读")
    func keepAliveAReply() throws {
        let session = try Fixtures.session()
        guard let reply = session.first("s2c", length: 72) else { return }
        let status = try DrcomCodec().parseKeepAliveAReply(Data(reply))
        #expect(status.session == 0x631D)
        #expect(status.stats.first == 732)          // 0xdc02 会话别名
        #expect(status.secondsOnline == 38)         // 实测随秒递增
        #expect(status.stats.count == 6)
    }

    @Test("保活 B 的第 1、第 2 包都能逐字节复现")
    func keepAliveBPair() throws {
        let session = try Fixtures.session()
        let captured = session.all("c2s", length: 40)
        #expect(captured.count == 12)
        guard captured.count >= 2 else { return }
        let codec = DrcomCodec()
        let first = KeepAliveBContext(
            round: 0x05, seq: 0x01, session: 0x02DC, timestamp: 0x0073B8E4,
            mirror: 0x4CF8447A, check: 0, clientIP: nil)
        #expect(hexString([UInt8](try codec.makeKeepAliveB(first))) == hexString(captured[0]))

        let second = KeepAliveBContext(
            round: 0x06, seq: 0x03, session: 0x02DC, timestamp: 0x0073B8E4,
            mirror: 0x4CF84672, check: 0x00F171C9,
            clientIP: IPv4Address("192.0.2.10"))
        #expect(hexString([UInt8](try codec.makeKeepAliveB(second))) == hexString(captured[1]))
        #expect(Array([UInt8](try codec.makeKeepAliveB(second))[0x1C..<0x20]) == [192, 0, 2, 10])
    }

    @Test("保活 B 应答：序号与请求共用一个自增计数（请求 01 → 应答 02）")
    func keepAliveBReply() throws {
        let session = try Fixtures.session()
        let replies = session.all("s2c", length: 40)
        guard let reply = replies.first else { return }
        let parsed = try DrcomCodec().parseKeepAliveBReply(Data(reply))
        #expect(parsed.round == 0x05)
        #expect(parsed.seq == 0x02)
        #expect(parsed.session == 0x02DC)
        #expect(parsed.mirror == 0x4CF84672)
    }

    @Test("长度不对的保活包必须报错")
    func wrongLength() throws {
        let codec = DrcomCodec()
        #expect(throws: DrcomError.self) {
            _ = try codec.parseKeepAliveAReply(Data(repeating: 0x07, count: 71))
        }
        #expect(throws: DrcomError.self) {
            _ = try codec.parseKeepAliveBReply(Data(repeating: 0x07, count: 39))
        }
    }
}

@Suite("帧识别")
struct FrameClassificationTests {
    @Test("抓包里 50 个载荷一个都不能落进 unknown")
    func noUnknownFrames() throws {
        let session = try Fixtures.session()
        let codec = DrcomCodec()
        for (index, frame) in session.frames.enumerated() {
            let classified = codec.classify(Data(frame.payload))
            if case .unknown(let type, let subtype, let length) = classified {
                Issue.record("第 \(index) 帧未识别：type=\(type) subtype=\(subtype) len=\(length)")
            }
        }
    }

    @Test("长度不符的要落进 unknown，而不是崩")
    func unknownLength() {
        let codec = DrcomCodec()
        let frame = codec.classify(Data([0x01, 0x03, 0x1D, 0x63, 0x31]))
        #expect(frame == .unknown(type: 0x01, subtype: 0x03, length: 5))
    }

    @Test("关键帧归类正确")
    func keyFrames() throws {
        let session = try Fixtures.session()
        let codec = DrcomCodec()
        var kinds: [String] = []
        for frame in session.frames {
            let classified = codec.classify(Data(frame.payload))
            switch classified {
            case .challenge: kinds.append("challenge")
            case .challengeReply: kinds.append("challengeReply")
            case .accountProbe: kinds.append("accountProbe")
            case .genericAck: kinds.append("genericAck")
            case .login: kinds.append("login")
            case .loginSuccess: kinds.append("loginSuccess")
            case .loginFailure: kinds.append("loginFailure")
            case .keepAliveARequest: kinds.append("keepAliveARequest")
            case .keepAliveAReply: kinds.append("keepAliveAReply")
            case .keepAliveBRequest: kinds.append("keepAliveB")
            case .keepAliveBReply: kinds.append("keepAliveB")
            case .unknown: kinds.append("unknown")
            }
        }
        #expect(kinds.filter { $0 == "challenge" }.count == 3)
        #expect(kinds.filter { $0 == "challengeReply" }.count == 3)
        #expect(kinds.filter { $0 == "login" }.count == 2)
        #expect(kinds.filter { $0 == "loginSuccess" }.count == 1)
        #expect(kinds.filter { $0 == "loginFailure" }.count == 1)
        #expect(kinds.filter { $0 == "keepAliveARequest" }.count == 7)
        #expect(kinds.filter { $0 == "keepAliveAReply" }.count == 7)
        #expect(kinds.filter { $0 == "keepAliveB" }.count == 24)
    }
}

@Suite("网关实际回包：272 字节的保活 B 应答")
struct KeepAliveBLongReplyTests {
    /// 真机日志里的头部：07 06 10 01 0b 06 dc 02 ...
    private var payload: Data {
        var bytes: [UInt8] = [
            0x07, 0x06, 0x10, 0x01, 0x0B, 0x06, 0xDC, 0x02,
            0x7C, 0x4A, 0xED, 0x6A, 0x00, 0x00, 0x00, 0x00,
            0xA8, 0xAC, 0x00, 0x00, 0x4F, 0xE4, 0x16, 0xC1,
            0x00, 0x00, 0x00, 0x00, 0xDC, 0x02, 0x00, 0x00,
        ]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 272 - bytes.count))
        return Data(bytes)
    }

    @Test("272 字节的类型 7 报文要认成保活 B 应答，而不是未知报文")
    func classify() {
        let frame = DrcomCodec().classify(payload)
        guard case .keepAliveBReply(let reply) = frame else {
            Issue.record("分类结果不是 keepAliveBReply：\(frame)")
            return
        }
        #expect(reply.round == 0x06)
        #expect(reply.seq == 0x06)
        #expect(reply.session == 0x02DC)
        #expect(reply.raw.count == 272)
    }
}
