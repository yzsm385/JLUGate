import Foundation

/// 日志/诊断里用的十六进制格式化（协议调试需要原样字节）。
public enum Hex {
    public static func string(_ bytes: [UInt8], limit: Int? = nil) -> String {
        let slice = limit.map { Array(bytes.prefix($0)) } ?? bytes
        return slice.map { String(format: "%02x", $0) }.joined()
    }

    public static func string(_ data: Data, limit: Int? = nil) -> String {
        string([UInt8](data), limit: limit)
    }
}
