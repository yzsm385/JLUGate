import Foundation

/// GPA 网页（gpa/）里的学院代码。
///
/// 这套代码来自教务系统培养方案索引（`gpa/data/plans-index.js`），和
/// 网络登录账号里的「专业/学院代码」一致。App 只负责把「学号/账号 → 学院 + 年级」
/// 这一步做掉，专业仍然交给网页让用户自己选。
public struct GPACollege: Sendable, Equatable, Identifiable, Hashable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// 学号 / 邮箱前缀的解析结果。
public struct GPACollegeMatch: Sendable, Equatable {
    /// 命中的学院；代码不在培养方案库里时为 nil（但 `code` 仍会保留）
    public let college: GPACollege?
    public let code: String?
    public let year: Int?

    public init(college: GPACollege?, code: String?, year: Int?) {
        self.college = college
        self.code = code
        self.year = year
    }
}

/// 学院目录 + 学号/账号解析。
///
/// 规则与网页端 `gpa/assets/landing-*.js` 的 `parseAccount` 保持一致：
/// - 学号是「代码 + 2 位入学年份 + 班号 + 序号」，代码在最前面，按最长匹配；
/// - 邮箱前缀是「姓名拼音 + 代码 + 2 位年份」，代码前必须是字母；
/// - 4 位纯数字只当年级（后两位），不猜学院；
/// - 认不出就返回 nil，绝不瞎猜。
public enum GPACollegeDirectory {
    /// 与 `gpa/data/plans-index.js` 的 48 个学院保持一致。
    public static let all: [GPACollege] = [
        GPACollege(code: "01", name: "哲学社会学院"),
        GPACollege(code: "02", name: "文学院"),
        GPACollege(code: "03", name: "外国语学院"),
        GPACollege(code: "04", name: "艺术学院"),
        GPACollege(code: "05", name: "体育学院"),
        GPACollege(code: "06", name: "经济学院"),
        GPACollege(code: "07", name: "法学院"),
        GPACollege(code: "08", name: "行政学院"),
        GPACollege(code: "10", name: "数学学院"),
        GPACollege(code: "11", name: "物理学院"),
        GPACollege(code: "12", name: "化学学院"),
        GPACollege(code: "13", name: "生命科学学院"),
        GPACollege(code: "14", name: "机械与航空航天工程学院"),
        GPACollege(code: "15", name: "汽车工程学院"),
        GPACollege(code: "16", name: "材料科学与工程学院"),
        GPACollege(code: "17", name: "交通学院"),
        GPACollege(code: "18", name: "生物与农业工程学院"),
        GPACollege(code: "19", name: "电子科学与工程学院"),
        GPACollege(code: "20", name: "通信工程学院"),
        GPACollege(code: "21", name: "计算机科学与技术学院"),
        GPACollege(code: "22", name: "地球科学学院"),
        GPACollege(code: "23", name: "地球探测科学与技术学院"),
        GPACollege(code: "24", name: "建设工程学院"),
        GPACollege(code: "25", name: "新能源与环境学院"),
        GPACollege(code: "27", name: "公共卫生学院"),
        GPACollege(code: "28", name: "药学院"),
        GPACollege(code: "29", name: "护理学院"),
        GPACollege(code: "30", name: "东北亚学院"),
        GPACollege(code: "31", name: "历史文化学院"),
        GPACollege(code: "33", name: "口腔医学院"),
        GPACollege(code: "35", name: "商学与管理学院"),
        GPACollege(code: "36", name: "公共外交学院"),
        GPACollege(code: "37", name: "新闻与传播学院"),
        GPACollege(code: "38", name: "考古学院"),
        GPACollege(code: "39", name: "马克思主义学院"),
        GPACollege(code: "40", name: "人工智能学院"),
        GPACollege(code: "55", name: "软件学院"),
        GPACollege(code: "65", name: "仪器科学与电气工程学院"),
        GPACollege(code: "71", name: "基础医学院"),
        GPACollege(code: "72", name: "白求恩医学部（第一临床医学院）"),
        GPACollege(code: "75", name: "白求恩第一临床医学院"),
        GPACollege(code: "76", name: "白求恩第二临床医学院"),
        GPACollege(code: "77", name: "白求恩第三临床医学院"),
        GPACollege(code: "78", name: "白求恩医学部（基础医学院）"),
        GPACollege(code: "81", name: "动物医学学院"),
        GPACollege(code: "82", name: "植物科学学院"),
        GPACollege(code: "85", name: "动物科学学院"),
        GPACollege(code: "87", name: "食品科学与工程学院"),
    ]

    /// 长代码优先，避免把后面的数字误当学院代码。
    private static let codesByLength: [String] = {
        Array(Set(all.map(\.code))).sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }
    }()

    /// 院系简称的固定写法 / 别名（App 的学院名与 GPA 网页不完全一致）。
    private static let nameAliases: [String: String] = [
        // App 的学院目录叫「外国语言文化学院」，培养方案库里叫「外国语学院」。
        "外国语言文化": "外国语",
        // 口腔医学院在 App 里叫「白求恩口腔医学院」，去掉前缀后仍能靠包含匹配到。
        "白求恩口腔医学": "口腔医学",
    ]

    public static func college(code: String) -> GPACollege? {
        let key = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return nil }
        return all.first { $0.code == key }
    }

    public static func college(forName raw: String) -> GPACollege? {
        let key = normalizeName(raw)
        guard !key.isEmpty else { return nil }
        let aliased = nameAliases[key] ?? key
        if let exact = all.first(where: { normalizeName($0.name) == aliased }) {
            return exact
        }
        // 兜底只做「包含」匹配，并取名字最长的那个，避免「基础医学」误配到
        // 「白求恩医学部（基础医学院）」这种更长的条目。
        let candidates = all.filter {
            let name = normalizeName($0.name)
            return name.contains(aliased) || aliased.contains(name)
        }
        return candidates.max { normalizeName($0.name).count < normalizeName($1.name).count }
    }

    public static func search(_ keyword: String) -> [GPACollege] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    /// 从学号或邮箱前缀识别学院 + 年级。
    public static func match(_ raw: String) -> GPACollegeMatch? {
        let s = normalizeAccount(raw)
        guard !s.isEmpty else { return nil }

        // 纯数字：4 位只认年级；≥6 位按「代码 + 6 位后缀」或「代码 + 2 位年份」。
        if s.allSatisfy(\.isNumber) {
            if s.count == 4 {
                guard let year = year(from: s.dropFirst(2)) else { return nil }
                return GPACollegeMatch(college: nil, code: nil, year: year)
            }
            guard s.count >= 6 else { return nil }
            for code in codesByLength where s.hasPrefix(code) {
                let rest = s.dropFirst(code.count)
                guard rest.count == 2 || rest.count == 6, let year = year(from: rest) else { continue }
                return GPACollegeMatch(college: college(code: code), code: code, year: year)
            }
            return nil
        }

        // 邮箱前缀：姓名拼音 + 代码 + 年份（+ 班号/序号），代码前必须是字母，
        // 且余下只能是 2 位年份或 6 位完整学号后缀。
        for code in codesByLength {
            var from = s.startIndex
            while let range = s.range(of: code, range: from..<s.endIndex) {
                let previous = range.lowerBound > s.startIndex
                    ? s[s.index(before: range.lowerBound)]
                    : nil
                let rest = s[range.upperBound...]
                let boundary = previous == nil || previous!.isLetter
                if boundary, rest.count == 2 || rest.count == 6, let year = year(from: rest) {
                    return GPACollegeMatch(college: college(code: code), code: code, year: year)
                }
                from = s.index(after: range.lowerBound)
            }
        }
        return nil
    }

    // MARK: - 内部

    private static func normalizeAccount(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let at = s.firstIndex(of: "@") { s = String(s[..<at]) }
        return String(s.filter { $0.isLetter || $0.isNumber })
    }

    private static func normalizeName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["学院", "学部", "系"] {
            s = s.replacingOccurrences(of: suffix, with: "")
        }
        s = s.replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return String(s.filter { !$0.isWhitespace })
    }

    private static func year(from rest: Substring) -> Int? {
        guard rest.count >= 2 else { return nil }
        let prefix = rest.prefix(2)
        guard prefix.allSatisfy(\.isNumber), let yy = Int(prefix), (10...40).contains(yy) else {
            return nil
        }
        return 2000 + yy
    }
}

/// GPA 网页深链。
///
/// 账号 / 学号只放在 fragment 里：fragment 不会发到服务器，也不会进访问日志。
/// 能确定学院时只传 `college` + `year`，连学号都不用带。
public enum GPALink {
    public static let base = URL(string: "https://yzsm385.github.io/JLUGate/")!

    public static func make(collegeCode: String?,
                            year: Int?,
                            studentID: String?,
                            account: String?) -> URL {
        var items: [URLQueryItem] = []
        let code = collegeCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty {
            items.append(URLQueryItem(name: "college", value: code))
        }
        if let year {
            items.append(URLQueryItem(name: "year", value: String(year)))
        }
        // 学院已经确定时不再把账号/学号交给网页；认不出学院才带一个身份提示，
        // 让网页端再按同一套规则认一次。学生账号本身就是「拼音 + 代码 + 年份」，
        // 所以优先带账号，不要求用户额外填学号。
        if code.isEmpty {
            let acct = account?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sid = studentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !acct.isEmpty {
                items.append(URLQueryItem(name: "account", value: acct))
            } else if !sid.isEmpty {
                items.append(URLQueryItem(name: "sid", value: sid))
            }
        }
        guard !items.isEmpty else { return base }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        // 先借 queryItems 做一次正确的百分号编码，再把结果挪到 fragment。
        components.queryItems = items
        let encoded = components.percentEncodedQuery ?? ""
        components.query = nil
        components.fragment = encoded
        return components.url ?? base
    }
}
