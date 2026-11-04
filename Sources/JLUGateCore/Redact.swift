import Foundation

/// 日志与诊断里的脱敏。
///
/// 原则：**诊断文件是给人看的，不是给攻击者看的。** 账号、学号、主机名、MAC
/// 都不需要完整出现就能排障，所以默认只保留最少的前缀。
public enum Redact {
    /// 账号：保留前 3 位（hu***），足够区分"是不是这个号"，但拼不出完整账号。
    public static func account(_ value: String) -> String {
        guard !value.isEmpty else { return "-" }
        let prefix = value.prefix(3)
        return value.count <= 3 ? String(prefix) + "***" : String(prefix) + "***"
    }

    /// 学号：只保留入学年份（2023****），学院靠前缀识别，日志不需要完整学号。
    public static func studentID(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else { return "-" }
        return String(digits.prefix(4)) + String(repeating: "*", count: max(digits.count - 4, 2))
    }

    /// MAC：保留前三段（厂商段），后三段打码。
    public static func mac(_ value: String) -> String {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 6 else { return "**:**:**:**:**:**" }
        return parts.prefix(3).joined(separator: ":") + ":**:**:*"
    }

    /// 主机名：保留前 3 个字符。
    public static func hostname(_ value: String) -> String {
        guard !value.isEmpty else { return "-" }
        return String(value.prefix(3)) + "***"
    }

    /// 从一段十六进制报文中抹掉账号（用于必须打印报文时的排障）。
    public static func scrubAccount(in hex: String, account: String) -> String {
        guard !account.isEmpty else { return hex }
        let needle = account.utf8.map { String(format: "%02x", $0) }.joined()
        guard let range = hex.range(of: needle, options: .caseInsensitive) else { return hex }
        let replacement = String(repeating: "2a", count: account.utf8.count)   // 2a = '*'
        return hex.replacingCharacters(in: range, with: replacement)
    }
}
