import Foundation

/// IPv4 地址（字节序即网络序）。
public struct IPv4Address: Sendable, Hashable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 4 else { return nil }
        self.bytes = bytes
    }

    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            result.append(value)
        }
        self.bytes = result
    }

    public var description: String {
        bytes.map(String.init).joined(separator: ".")
    }

    public var uint32BE: UInt32 {
        UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    public static let zero = IPv4Address(bytes: [0, 0, 0, 0])!
}

/// MAC 地址（`aa:bb:cc:dd:ee:ff` 或 6 字节原始值）。
public struct MACAddress: Sendable, Hashable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 6 else { return nil }
        self.bytes = bytes
    }

    public init?(_ string: String) {
        let parts = string.split(separator: ":").isEmpty
            ? string.split(separator: "-")
            : string.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var result: [UInt8] = []
        for part in parts {
            guard part.count == 2, let value = UInt8(part, radix: 16) else { return nil }
            result.append(value)
        }
        self.bytes = result
    }

    public var description: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// 本地管理地址（第一个字节的 U/L 位 = 1）：
    /// 这类 MAC 是**软件生成**的（macOS 的"私有地址"/随机 MAC、或手动改过 MAC），
    /// 不是网卡出厂的那一个。`f2:..`、`02:..`、`6a:..` 都是这一类。
    public var isLocallyAdministrated: Bool {
        guard let first = bytes.first else { return false }
        return (first & 0x02) != 0
    }

    /// 忽略大小写与分隔符的比较。
    public func matches(_ other: MACAddress?) -> Bool {
        guard let other else { return false }
        return bytes == other.bytes
    }
}
