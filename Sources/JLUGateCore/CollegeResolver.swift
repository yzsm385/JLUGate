import Foundation

/// 学号 → 学院：用"前缀学习"而不是编造官方对照表。
///
/// 吉大官方没有公开学院代码表，硬编码一份"猜的"只会把人导到错误的学院。
/// 这里的做法：
/// 1. 从学号里取两个前缀：前 4 位（入学年份）和前 6 位（年份 + 学院码）；
/// 2. 查本机保存的映射（用户第一次手选学院后写入）；
/// 3. 查不到就返回 nil，由界面提示"选一次，之后自动"。
public enum CollegeResolver {
    /// 前缀长度：6 位（年份+学院）优先，其次 4 位（只有年份，作为兜底）。
    public static let prefixLengths = [6, 4]

    public static func prefix(of studentID: String, length: Int) -> String? {
        let digits = studentID.filter(\.isNumber)
        guard digits.count >= length else { return nil }
        return String(digits.prefix(length))
    }

    /// - Parameters:
    ///   - studentID: 学号（可含空格/连字符，内部会过滤）
    ///   - learned: 前缀 → 学院官网 host
    public static func resolve(studentID: String,
                               learned: [String: String]) -> College? {
        for length in prefixLengths {
            guard let key = prefix(of: studentID, length: length),
                  let host = learned[key],
                  let college = CollegeDirectory.college(forHost: host) else { continue }
            return college
        }
        return nil
    }

    /// 学号是否像"吉大学号"：纯数字 8~14 位。只用来给界面提示，不做强制。
    public static func looksLikeStudentID(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        return digits == text.filter({ !$0.isWhitespace && $0 != "-" }) && (8...14).contains(digits.count)
    }

    /// 记住"这个学号属于这个学院"：同时写 6 位与 4 位前缀（4 位作为兜底）。
    public static func learn(studentID: String, college: College,
                             into learned: inout [String: String]) {
        for length in prefixLengths {
            guard let key = prefix(of: studentID, length: length) else { continue }
            // 4 位前缀只是兜底：已被别的学院占用时不覆盖，避免同届误判
            if length == 4, let existing = learned[key], existing != college.host { continue }
            learned[key] = college.host
        }
    }
}
