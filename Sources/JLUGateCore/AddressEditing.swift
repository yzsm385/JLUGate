import Foundation

/// 地址输入的编辑规则（纯函数，便于单测）。
///
/// 关键约束：**只有"在末尾继续输入"才重排并补分隔符**；
/// 在中间插入/删除时保持原样，这样光标不会被踢到末尾——
/// 真机上出现"改不了前面、只能整行清空"就是因为每敲一个字符都重排。
public enum AddressEditing {
    public enum Kind: Sendable, Equatable {
        case ipv4
        case mac

        var separator: Character { self == .ipv4 ? "." : ":" }
        func isAllowed(_ character: Character) -> Bool {
            self == .mac ? character.isHexDigit : character.isNumber
        }
        func format(_ raw: String) -> String {
            self == .ipv4 ? FieldFormatting.liveIPv4(raw) : FieldFormatting.liveMAC(raw)
        }
    }

    public struct Result: Sendable, Equatable {
        public let text: String
        public let caret: Int
    }

    /// 保留原分组：每组只留合法字符、按组上限截断，段数不超过上限。
    static func normalize(_ typed: String, kind: Kind) -> String {
        let groupSize = kind == .ipv4 ? 3 : 2
        let maxGroups = kind == .ipv4 ? 4 : 6
        var groups: [String] = []
        for part in typed.split(separator: kind.separator, omittingEmptySubsequences: false) {
            if groups.count == maxGroups { break }
            let cleaned = part.filter { kind.isAllowed($0) }
            groups.append(String(cleaned.prefix(groupSize)))
        }
        var result = groups.joined(separator: String(kind.separator))
        if let last = groups.last, last.count == groupSize, groups.count < maxGroups {
            result.append(kind.separator)
        }
        return result
    }

    /// - Parameters:
    ///   - typed: 输入框当前的完整文本（编辑器里的字符串）
    ///   - selectedLocation: 输入后的光标位置（UTF-16 偏移；与 NSRange 一致）
    public static func apply(typed: String, selectedLocation: Int, kind: Kind) -> Result {
        var filtered = ""
        for character in typed {
            if character == kind.separator || kind.isAllowed(character) {
                filtered.append(character)
            }
        }

        // 判断是否"在末尾继续输入"：过滤掉非法字符后，光标仍落在文本末尾
        let typingAtEnd = selectedLocation >= filtered.count
        guard typingAtEnd else {
            // 中间编辑：原样返回，光标不动
            return Result(text: filtered,
                          caret: max(0, min(selectedLocation, filtered.count)))
        }

        // 已经带分隔符的（粘贴、或用户自己打了点）：按原分组规整，别跨组重排
        let formatted = typed.contains(kind.separator)
            ? normalize(typed, kind: kind)
            : kind.format(filtered)
        return Result(text: formatted, caret: formatted.count)
    }
}
