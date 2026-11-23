import Foundation

/// 专属学院的识别来源。
public enum CollegeResolutionSource: Equatable, Sendable {
    /// 用户手动指定
    case manual
    /// 按学号中的学院代码自动识别
    case studentID
    /// 复用校园网登录账号（邮箱前缀）中的学院代码自动识别
    case account
    /// 命中本机已学习的前缀映射
    case learned
}

/// 专属学院统一识别结果。
public struct CollegeResolution: Equatable, Sendable {
    public let college: College
    public let source: CollegeResolutionSource
    public let year: Int?

    public init(college: College, source: CollegeResolutionSource, year: Int?) {
        self.college = college
        self.source = source
        self.year = year
    }
}

/// 学号 / 校园网账号 → 专属学院统一识别器。
///
/// 识别优先级：
/// 1. 手动选定的学院官网 host（支持转专业/跨院覆盖）；
/// 2. 学号（通过 `GPACollegeDirectory` 学院代码表直接识别，兜底本机学习前缀表）；
/// 3. 校园网登录账号/邮箱前缀（如 `zhangsan5525` 直接复用，无需重复输入或搜索）。
public enum CollegeResolver {
    /// 前缀长度：6 位（年份+学院）优先，其次 4 位（只有年份，作为兜底）。
    public static let prefixLengths = [6, 4]

    public static func prefix(of studentID: String, length: Int) -> String? {
        let digits = studentID.filter(\.isNumber)
        guard digits.count >= length else { return nil }
        return String(digits.prefix(length))
    }

    /// 统一解析专属学院（复用手动设置、学号、校园网账号与本机学习映射）。
    public static func resolve(manualHost: String = "",
                               studentID: String,
                               account: String = "",
                               learned: [String: String]) -> CollegeResolution? {
        let sidMatch = GPACollegeDirectory.match(studentID)
        let acctMatch = GPACollegeDirectory.match(account)
        let year = sidMatch?.year ?? acctMatch?.year

        if !manualHost.isEmpty,
           let manual = CollegeDirectory.college(forHost: manualHost) {
            return CollegeResolution(college: manual, source: .manual, year: year)
        }

        if let gpaCollege = sidMatch?.college,
           let college = CollegeDirectory.college(forGPACollege: gpaCollege) {
            return CollegeResolution(college: college, source: .studentID, year: sidMatch?.year)
        }

        if let learnedCollege = resolveLearned(studentID: studentID, learned: learned) {
            return CollegeResolution(college: learnedCollege, source: .learned, year: year)
        }

        if let gpaCollege = acctMatch?.college,
           let college = CollegeDirectory.college(forGPACollege: gpaCollege) {
            return CollegeResolution(college: college, source: .account, year: acctMatch?.year)
        }

        if !account.isEmpty,
           let learnedCollege = resolveLearned(studentID: account, learned: learned) {
            return CollegeResolution(college: learnedCollege, source: .learned, year: year)
        }

        return nil
    }

    /// - Parameters:
    ///   - studentID: 学号（可含空格/连字符，内部会过滤）
    ///   - learned: 前缀 → 学院官网 host
    public static func resolve(studentID: String,
                               learned: [String: String]) -> College? {
        resolve(studentID: studentID, learned: learned)?.college
    }

    private static func resolveLearned(studentID: String,
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
