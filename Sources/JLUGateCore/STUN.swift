import Foundation

/// 最小 STUN 客户端（RFC 5389 绑定请求 / 响应）：
/// 用来问"外界看到的我是哪个 IP"——这正是浏览器 WebRTC 泄漏检测的同一套机制。
public enum STUN {
    /// 绑定请求（20 字节，无属性）。
    public static func bindingRequest() -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += [0x00, 0x01]                 // Binding Request
        bytes += [0x00, 0x00]                 // length = 0
        bytes += [0x21, 0x12, 0xA4, 0x42]     // magic cookie
        bytes += (0..<12).map { _ in UInt8.random(in: 0...255) }  // transaction id
        return bytes
    }

    public struct Result: Sendable, Equatable {
        public let mappedAddress: String?
        public let mappedPort: UInt16?
        public let otherAddress: String?
    }

    public enum ParseError: Error, Equatable {
        case tooShort
        case notBindingSuccess
        case noMappedAddress
    }

    /// 解析 Binding Success Response，取 XOR-MAPPED-ADDRESS（或 MAPPED-ADDRESS）。
    public static func parseBindingResponse(_ data: Data) throws -> Result {
        let bytes = [UInt8](data)
        guard bytes.count >= 20 else { throw ParseError.tooShort }
        let type = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard type == 0x0101 else { throw ParseError.notBindingSuccess }
        let length = Int(UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
        var index = 20
        let end = min(bytes.count, 20 + length)

        var mapped: (String, UInt16)?
        var other: String?

        while index + 4 <= end {
            let attrType = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            let attrLen = Int(UInt16(bytes[index + 2]) << 8 | UInt16(bytes[index + 3]))
            let valueStart = index + 4
            let valueEnd = valueStart + attrLen
            guard valueEnd <= bytes.count else { break }

            switch attrType {
            case 0x0020:   // XOR-MAPPED-ADDRESS
                if let parsed = parseAddress(bytes, from: valueStart, length: attrLen, xor: true) {
                    mapped = parsed
                }
            case 0x0001:   // MAPPED-ADDRESS（老式）
                if mapped == nil,
                   let parsed = parseAddress(bytes, from: valueStart, length: attrLen, xor: false) {
                    mapped = parsed
                }
            case 0x802C:   // OTHER-ADDRESS（部分服务商返回）
                if let parsed = parseAddress(bytes, from: valueStart, length: attrLen, xor: false) {
                    other = parsed.0
                }
            default:
                break
            }
            // 4 字节对齐
            index = valueEnd + ((4 - attrLen % 4) % 4)
        }

        guard let mapped else { throw ParseError.noMappedAddress }
        return Result(mappedAddress: mapped.0, mappedPort: mapped.1, otherAddress: other)
    }

    private static func parseAddress(_ bytes: [UInt8], from start: Int,
                                     length: Int, xor: Bool) -> (String, UInt16)? {
        guard length >= 8, start + 8 <= bytes.count else { return nil }
        let family = bytes[start + 1]
        guard family == 0x01 else { return nil }   // 只处理 IPv4（够用）
        var port = UInt16(bytes[start + 2]) << 8 | UInt16(bytes[start + 3])
        var address = Array(bytes[(start + 4)..<(start + 8)])
        if xor {
            port ^= 0x2112
            let cookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
            for i in 0..<4 { address[i] ^= cookie[i] }
        }
        return ("\(address[0]).\(address[1]).\(address[2]).\(address[3])", port)
    }
}

/// Cloudflare `cdn-cgi/trace` 的解析结果。
public struct CloudflareTrace: Sendable, Equatable {
    public var ip: String?
    public var location: String?      // 国家码，如 JP / SG / CN
    public var colo: String?          // 边缘机房，如 HKG / NRT
    public var warp: String?          // on / off
    public var tls: String?
    public var http: String?
    public var sni: String?

    /// 解析 `key=value` 每行一对的文本。
    public static func parse(_ text: String) -> CloudflareTrace {
        var trace = CloudflareTrace()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "ip": trace.ip = value
            case "loc": trace.location = value
            case "colo": trace.colo = value
            case "warp": trace.warp = value
            case "tls": trace.tls = value
            case "http": trace.http = value
            case "sni": trace.sni = value
            default: break
            }
        }
        return trace
    }

    /// 一句人话：出口在哪个国家的哪个机房。
    public var summary: String? {
        guard let ip else { return nil }
        var parts = [ip]
        if let location { parts.append("出口国家/地区 \(location)") }
        if let colo { parts.append("Cloudflare 机房 \(colo)") }
        return parts.joined(separator: " · ")
    }
}
