import Foundation

/// 输入框的分隔符自动补全：用户只管敲数字/十六进制，点号与冒号由程序补。
///
/// 这些值本来就要人工照抄（学校按端口分配），再让用户手打 `.` 和 `:` 只会增加抄错的机会。
public enum FieldFormatting {
    /// IPv4：每段最多 3 位数字，段间自动补 `.`，最多 4 段。
    /// 输满 3 位就自动补点，等于把"下一段"替你打开。
    public static func ipv4Input(_ raw: String) -> String {
        let hadTrailingDot = raw.hasSuffix(".")
        let groups = raw.split(separator: ".", omittingEmptySubsequences: true)
            .map { String($0.filter(\.isNumber).prefix(3)) }
            .filter { !$0.isEmpty }
            .prefix(4)
        guard !groups.isEmpty else { return "" }

        var result = groups.joined(separator: ".")
        guard groups.count < 4 else { return result }
        if hadTrailingDot {
            result += "."
        } else if groups.last?.count == 3 {
            result += "."     // 满 3 位自动补点
        }
        return result
    }

    /// MAC：每 2 个十六进制字符自动补 `:`，最多 6 段。
    public static func macInput(_ raw: String) -> String {
        let hex = raw.filter(\.isHexDigit).lowercased()
        let limited = String(hex.prefix(12))
        var parts: [String] = []
        var index = limited.startIndex
        while index < limited.endIndex {
            let next = limited.index(index, offsetBy: 2, limitedBy: limited.endIndex) ?? limited.endIndex
            parts.append(String(limited[index..<next]))
            index = next
        }
        guard !parts.isEmpty else { return "" }
        var result = parts.joined(separator: ":")
        // 正好 2 的倍数且还没满 6 段时，末尾补冒号方便继续输入
        if limited.count % 2 == 0, parts.count < 6 {
            result += ":"
        }
        return result
    }

    /// 边输入边补分隔符（单行输入框用）：满 3 位补点，最多 4 段。
    /// 光标稳定：只在字符数增加时格式化，不改动中间已存在的内容。
    public static func liveIPv4(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).prefix(12)
        var groups: [String] = []
        var current = ""
        for character in digits {
            current.append(character)
            if current.count == 3 { groups.append(current); current = "" }
        }
        if !current.isEmpty { groups.append(current) }
        var result = groups.joined(separator: ".")
        if !digits.isEmpty, digits.count % 3 == 0, groups.count < 4 { result += "." }
        return result
    }

    /// MAC：每 2 位补冒号，最多 6 段。
    public static func liveMAC(_ raw: String) -> String {
        let hex = raw.filter(\.isHexDigit).lowercased().prefix(12)
        var groups: [String] = []
        var current = ""
        for character in hex {
            current.append(character)
            if current.count == 2 { groups.append(current); current = "" }
        }
        if !current.isEmpty { groups.append(current) }
        var result = groups.joined(separator: ":")
        if !hex.isEmpty, hex.count % 2 == 0, groups.count < 6 { result += ":" }
        return result
    }

    /// 把一段 IPv4 文本拆成 4 个小段（给"四格输入"用，界面上只显示点号，不用手打）。
    public static func splitIPv4(_ text: String) -> [String] {
        var parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        while parts.count < 4 { parts.append("") }
        return Array(parts.prefix(4))
    }

    public static func joinIPv4(_ parts: [String]) -> String {
        let trimmed = parts.map { $0.filter(\.isNumber) }
        // 全空就当作没填
        if trimmed.allSatisfy({ $0.isEmpty }) { return "" }
        return trimmed.prefix(4).joined(separator: ".")
    }

    /// MAC 拆成 6 段（两格一组）。
    public static func splitMAC(_ text: String) -> [String] {
        let hex = text.filter(\.isHexDigit).lowercased()
        var parts: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex, parts.count < 6 {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            parts.append(String(hex[index..<next]))
            index = next
        }
        while parts.count < 6 { parts.append("") }
        return parts
    }

    public static func joinMAC(_ parts: [String]) -> String {
        let cleaned = parts.map { String($0.filter(\.isHexDigit).lowercased().prefix(2)) }
        if cleaned.allSatisfy({ $0.isEmpty }) { return "" }
        return cleaned.joined(separator: ":")
    }

    /// DNS：逗号分隔的多个 IPv4，逐个自动补点。
    public static func ipv4ListInput(_ raw: String) -> String {
        let pieces = raw.split(separator: ",", omittingEmptySubsequences: false)
        let formatted = pieces.map { ipv4Input(String($0).trimmingCharacters(in: .whitespaces)) }
        return formatted.joined(separator: ", ")
    }
}
