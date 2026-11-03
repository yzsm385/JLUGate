import Foundation

/// 极简 DNS（只做「查 A 记录」）。
///
/// 为什么自己查：PLAN §8.2 / CHECKLIST §7 —— 系统 DNS 被代理劫持成 fake-ip（198.18.x.x），
/// 用它解析出来的地址连不上真实目标，探针会永远"看起来正常"。所以探针自己向学校 DNS
/// 发 UDP 53 查询，拿到 **字面 IPv4** 再去连。
public enum DNSPacket {
    /// 组一个递归查询（QTYPE=A，QCLASS=IN）。
    public static func makeQuery(name: String, id: UInt16) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(12 + name.count + 6)
        bytes.append(UInt8(truncatingIfNeeded: id >> 8))
        bytes.append(UInt8(truncatingIfNeeded: id))
        bytes.append(contentsOf: [0x01, 0x00])   // RD=1
        bytes.append(contentsOf: [0x00, 0x01])   // QDCOUNT = 1
        bytes.append(contentsOf: [0x00, 0x00])   // ANCOUNT
        bytes.append(contentsOf: [0x00, 0x00])   // NSCOUNT
        bytes.append(contentsOf: [0x00, 0x00])   // ARCOUNT

        for label in name.split(separator: ".", omittingEmptySubsequences: true) {
            let raw = Array(label.utf8)
            bytes.append(UInt8(truncatingIfNeeded: min(raw.count, 63)))
            bytes.append(contentsOf: raw.prefix(63))
        }
        bytes.append(0)                                   // 根
        bytes.append(contentsOf: [0x00, 0x01])            // QTYPE = A
        bytes.append(contentsOf: [0x00, 0x01])            // QCLASS = IN
        return bytes
    }

    /// 从应答里取出全部 A 记录（忽略 CNAME 链，只收集最终地址）。
    public static func parseARecords(_ data: [UInt8]) throws -> [IPv4Address] {
        let reader = ByteReader(data)
        guard data.count >= 12 else { throw DrcomError.malformed("DNS 报文短于 12 字节") }

        let flags = try reader.u16(at: 2, endian: .big)
        let rcode = flags & 0x000F
        guard rcode == 0 else {
            throw DrcomError.malformed("DNS 应答错误码 rcode=\(rcode)")
        }
        let questionCount = try reader.u16(at: 4, endian: .big)
        let answerCount = try reader.u16(at: 6, endian: .big)

        var offset = 12
        for _ in 0..<Int(questionCount) {
            offset = try skipName(in: data, at: offset)
            guard offset + 4 <= data.count else {
                throw DrcomError.malformed("DNS 问题段越界")
            }
            offset += 4    // QTYPE + QCLASS
        }

        var addresses: [IPv4Address] = []
        for _ in 0..<Int(answerCount) {
            offset = try skipName(in: data, at: offset)
            guard offset + 10 <= data.count else {
                throw DrcomError.malformed("DNS 答案段越界")
            }
            let type = try reader.u16(at: offset, endian: .big)
            let klass = try reader.u16(at: offset + 2, endian: .big)
            let length = Int(try reader.u16(at: offset + 8, endian: .big))
            let payload = offset + 10
            guard payload + length <= data.count else {
                throw DrcomError.malformed("DNS 记录长度越界")
            }
            if type == 1, klass == 1, length == 4 {
                if let address = IPv4Address(bytes: try reader.slice(payload, 4)) {
                    addresses.append(address)
                }
            }
            offset = payload + length
        }
        return addresses
    }

    /// 跳过（可能是压缩指针的）域名，返回下一段的偏移。
    static func skipName(in data: [UInt8], at start: Int) throws -> Int {
        var offset = start
        while true {
            guard offset < data.count else { throw DrcomError.malformed("DNS 域名越界") }
            let length = data[offset]
            if length == 0 { return offset + 1 }
            if length & 0xC0 == 0xC0 {
                // 压缩指针：2 字节，指向别处，名称本身到此结束。
                guard offset + 2 <= data.count else { throw DrcomError.malformed("DNS 压缩指针越界") }
                return offset + 2
            }
            guard offset + 1 + Int(length) <= data.count else {
                throw DrcomError.malformed("DNS 标签越界")
            }
            offset += 1 + Int(length)
        }
    }
}
