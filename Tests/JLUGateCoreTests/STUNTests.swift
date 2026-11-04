import Foundation
import Testing
@testable import JLUGateCore

@Suite("STUN / Cloudflare 解析")
struct STUNTests {
    /// 构造一个 XOR-MAPPED-ADDRESS 绑定响应。
    private func response(ip: [UInt8], port: UInt16) -> Data {
        var body: [UInt8] = []
        body += [0x00, 0x20]                       // XOR-MAPPED-ADDRESS
        body += [0x00, 0x08]                       // 长度 8
        body += [0x00, 0x01]                       // reserved + family IPv4
        let xorPort = port ^ 0x2112
        body += [UInt8(xorPort >> 8), UInt8(xorPort & 0xFF)]
        let cookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
        body += (0..<4).map { ip[$0] ^ cookie[$0] }

        var packet: [UInt8] = [0x01, 0x01, 0x00, 0x00,
                               0x21, 0x12, 0xA4, 0x42,
                               0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11,
                               0x22, 0x33, 0x44, 0x55]
        packet[2] = UInt8(body.count >> 8)
        packet[3] = UInt8(body.count & 0xFF)
        return Data(packet + body)
    }

    @Test("解析 XOR-MAPPED-ADDRESS：拿到外界看到的 IP 与端口")
    func parseMapped() throws {
        let data = response(ip: [203, 0, 113, 7], port: 51515)
        let result = try STUN.parseBindingResponse(data)
        #expect(result.mappedAddress == "203.0.113.7")
        #expect(result.mappedPort == 51515)
    }

    @Test("绑定请求 20 字节、magic cookie 正确")
    func requestShape() {
        let request = STUN.bindingRequest()
        #expect(request.count == 20)
        #expect(Array(request[4..<8]) == [0x21, 0x12, 0xA4, 0x42])
        #expect(request[0] == 0x00 && request[1] == 0x01)
    }

    @Test("不是绑定成功响应就报错，不越界")
    func rejectsOtherTypes() {
        let data = Data([0x01, 0x11, 0x00, 0x00] + Array(repeating: 0, count: 16))
        #expect(throws: STUN.ParseError.self) { try STUN.parseBindingResponse(data) }
        #expect(throws: STUN.ParseError.tooShort) { try STUN.parseBindingResponse(Data([1, 2, 3])) }
    }

    @Test("Cloudflare trace 解析 + 一句话摘要")
    func cloudflareTrace() {
        let text = """
        fl=123f45
        h=www.cloudflare.com
        ip=198.51.100.9
        tls=TLSv1.3
        http=HTTP/1.1 200 OK
        loc=JP
        colo=NRT
        warp=off
        """
        let trace = CloudflareTrace.parse(text)
        #expect(trace.ip == "198.51.100.9")
        #expect(trace.location == "JP")
        #expect(trace.colo == "NRT")
        #expect(trace.summary?.contains("203") == false)
        #expect(trace.summary?.contains("NRT") == true)
    }
}
