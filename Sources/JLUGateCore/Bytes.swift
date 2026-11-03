/// 带边界检查的字节读写器。
///
/// 协议字段一律按绝对偏移读写（见 `PacketLayout`），因此这里把"偏移"作为第一等参数，
/// 而不是提供一个顺序游标。所有越界都会抛 `DrcomError.malformed`，绝不静默截断。
import Foundation

public struct ByteReader: Sendable {
    public let bytes: [UInt8]

    public init(_ data: Data) {
        self.bytes = Array(data)
    }

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var count: Int { bytes.count }

    public func u8(at offset: Int) throws -> UInt8 {
        try slice(offset, 1)[0]
    }

    public func u16(at offset: Int, endian: Endianness = .big) throws -> UInt16 {
        let b = try slice(offset, 2)
        return switch endian {
        case .big: UInt16(b[0]) << 8 | UInt16(b[1])
        case .little: UInt16(b[1]) << 8 | UInt16(b[0])
        }
    }

    public func u32(at offset: Int, endian: Endianness = .little) throws -> UInt32 {
        let b = try slice(offset, 4)
        return switch endian {
        case .big:
            UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        case .little:
            UInt32(b[3]) << 24 | UInt32(b[2]) << 16 | UInt32(b[1]) << 8 | UInt32(b[0])
        }
    }

    public func slice(_ offset: Int, _ length: Int) throws -> [UInt8] {
        guard offset >= 0, length >= 0, offset &+ length <= bytes.count else {
            throw DrcomError.malformed("读取越界：offset=\(offset) length=\(length) 实际=\(bytes.count)")
        }
        return Array(bytes[offset..<(offset + length)])
    }

    /// 读取 NUL 结尾的 ASCII 字符串（最多 `length` 字节），找不到 NUL 就取整段。
    public func cString(_ offset: Int, _ length: Int) throws -> String {
        let raw = try slice(offset, length)
        let end = raw.firstIndex(of: 0) ?? raw.count
        return String(decoding: raw[..<end], as: UTF8.self)
    }
}

public enum Endianness: Sendable {
    case big
    case little
}

public struct ByteWriter: Sendable {
    public private(set) var bytes: [UInt8]

    public init(count: Int) {
        self.bytes = [UInt8](repeating: 0, count: count)
    }

    public init() {
        self.bytes = []
    }

    public var count: Int { bytes.count }

    public mutating func put(_ value: UInt8, at offset: Int) throws {
        try ensure(offset, 1)
        bytes[offset] = value
    }

    public mutating func put(_ value: UInt16, at offset: Int, endian: Endianness = .big) throws {
        try ensure(offset, 2)
        switch endian {
        case .big:
            bytes[offset] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
        case .little:
            bytes[offset] = UInt8(truncatingIfNeeded: value)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        }
    }

    public mutating func put(_ value: UInt32, at offset: Int, endian: Endianness = .little) throws {
        try ensure(offset, 4)
        switch endian {
        case .big:
            bytes[offset] = UInt8(truncatingIfNeeded: value >> 24)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
            bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[offset + 3] = UInt8(truncatingIfNeeded: value)
        case .little:
            bytes[offset] = UInt8(truncatingIfNeeded: value)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
            bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
        }
    }

    public mutating func put(_ data: [UInt8], at offset: Int) throws {
        try ensure(offset, data.count)
        bytes.replaceSubrange(offset..<(offset + data.count), with: data)
    }

    public mutating func put(_ data: Data, at offset: Int) throws {
        try put(Array(data), at: offset)
    }

    /// 写 NUL 补齐的定长 ASCII 字段；超长报错（协议里定长字段绝不能截断）。
    ///
    /// 注意：抓包里的主机名 `test-mac.local`（26 字节）**正好填满**
    /// 0x06E–0x087 且没有结尾 NUL，所以这里允许"恰好等于长度"，不强制留 1 字节。
    public mutating func putCString(_ string: String, at offset: Int, length: Int) throws {
        let raw = Array(string.utf8)
        guard raw.count <= length else {
            throw DrcomError.fieldTooLong(field: string, max: length)
        }
        try ensure(offset, length)
        for index in 0..<length {
            bytes[offset + index] = index < raw.count ? raw[index] : 0
        }
    }

    public func data() -> Data {
        Data(bytes)
    }

    private func ensure(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset &+ length <= bytes.count else {
            throw DrcomError.malformed("写入越界：offset=\(offset) length=\(length) 容量=\(bytes.count)")
        }
    }
}
