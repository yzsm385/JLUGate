import Foundation

/// JLU 账号格式（用于向导里的实时指引）。
///
/// 账号就是学校邮箱 `@mails.jlu.edu.cn` 前面那一段：
/// - **学生**：姓全拼 + 名各字首字母 + 4 位数字（前 2 位专业代码、后 2 位入学年份），
///   例如 `zhangcyy2122`（计算机专业 22 年入学）；
/// - **教师**：姓名全拼，例如 `zhangshanwu`；**同名**时学校会加后缀，不遵循此规则。
/// 密码就是邮箱密码。
public enum AccountFormat {
    public static let mailDomain = "mails.jlu.edu.cn"

    public enum Kind: Sendable, Equatable {
        /// 学生：带 4 位数字后缀（专业代码 2 位 + 入学年份 2 位）
        case student(professionalCode: String, enrollmentYear: String)
        /// 教师（或同名变体）：纯字母
        case teacherOrVariant
        /// 认不出格式（例如手机号、纯数字学号）
        case unrecognized
    }

    public struct Analysis: Sendable, Equatable {
        public var normalized: String
        public var kind: Kind
        public var hint: String
        public var isLikelyValid: Bool { kind != .unrecognized }
    }

    /// 去掉邮箱域名、空格，统一小写。
    public static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let at = text.firstIndex(of: "@") {
            let domain = String(text[text.index(after: at)...])
            if domain.hasSuffix(mailDomain) || domain.hasSuffix("jlu.edu.cn") {
                text = String(text[..<at])
            } else {
                text = String(text[..<at])   // 粘贴成别的邮箱也按前缀算
            }
        }
        return text
    }

    public static func analyze(_ raw: String) -> Analysis {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else {
            return Analysis(normalized: "", kind: .unrecognized,
                            hint: Copy.f("B211", mailDomain))
        }
        guard normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return Analysis(normalized: normalized, kind: .unrecognized,
                            hint: Copy.t("B212"))
        }
        guard let firstDigit = normalized.firstIndex(where: { $0.isNumber }) else {
            // 纯字母：教师格式（或同名变体）
            return Analysis(normalized: normalized, kind: .teacherOrVariant,
                            hint: Copy.t("B213"))
        }
        let digits = normalized[firstDigit...]
        guard digits.count == 4, digits.allSatisfy(\.isNumber) else {
            return Analysis(normalized: normalized, kind: .unrecognized,
                            hint: Copy.t("B214"))
        }
        let codes = Array(digits)
        let professional = String(codes[0...1])
        let year = String(codes[2...3])
        return Analysis(
            normalized: normalized,
            kind: .student(professionalCode: professional, enrollmentYear: year),
            hint: Copy.f("B215", professional, year))
    }

    /// 向导里展示的格式说明（一段话，可直接给用户看）。
    public static let guidance = Copy.f("B216", mailDomain)
}
