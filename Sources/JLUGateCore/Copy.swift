import Foundation

/// 界面支持的语言。按系统首选语言自动选，也可以在启动时用 `JLUGATE_LANG=zh-Hans` 强制。
public enum CopyLanguage: String, Sendable, CaseIterable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"

    public var displayName: String {
        switch self {
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .en: "English"
        }
    }
}

/// 界面文案的统一入口。
///
/// 所有用户可见的文字都按 `docs/UI-COPY.md` 里的编号（M03、B1-12 这种）取：
/// `Copy.t("M03")` 取整句，`Copy.f("M15", a, b)` 按顺序填 `{…}` 占位符。
/// 三种语言（简体 / 繁體 / English）由系统首选语言决定，缺条目时回退简体。
/// 三张语言表（数值在 CopyTable-*.swift 里生成）
enum CopyTables {}

public enum Copy {
    public static let language: CopyLanguage = resolveLanguage()

    public static func t(_ key: String) -> String {
        if let value = table[language]?[key], !value.isEmpty { return value }
        if let fallback = table[.zhHans]?[key], !fallback.isEmpty { return fallback }
        return key
    }

    /// 按顺序填 `{…}`。参数用 `Any` 接，和 Swift 字符串插值 `\(x)` 的显示效果一致
    /// （Int / Optional / 自定义类型都行）。
    public static func f(_ key: String, _ args: Any...) -> String {
        substitute(t(key), args.map { "\($0)" })
    }

    /// 供诊断显示
    public static var currentLanguageName: String { language.displayName }

    /// 去掉 emoji / 变体选择符（底部工具栏已经有 SF Symbol 图标，emoji 只会把字挤到下一行）
    public static func withoutEmoji(_ text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            if scalar.value == 0xFE0F || scalar.value == 0x200D { return false }   // VS16 / ZWJ
            if scalar.properties.isEmojiPresentation { return false }
            if (0x1F000...0x1FAFF).contains(scalar.value) { return false }
            if (0x2600...0x27BF).contains(scalar.value) { return false }
            return true
        }
        return String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 按顺序替换 `{…}`；参数比占位符多时忽略多余参数，占位符比参数多时保留原样。
    static func substitute(_ template: String, _ args: [String]) -> String {
        guard !args.isEmpty else { return template }
        var result = template
        for arg in args {
            guard let range = result.range(of: "{…}") else { break }
            result.replaceSubrange(range, with: arg)
        }
        return result
    }

    static func resolveLanguage(environment: [String: String] = ProcessInfo.processInfo.environment,
                                preferred: [String] = Locale.preferredLanguages) -> CopyLanguage {
        if let forced = environment["JLUGATE_LANG"].flatMap(CopyLanguage.init(rawValue:)) {
            return forced
        }
        guard let first = preferred.first?.lowercased() else { return .en }
        if first.hasPrefix("zh") {
            // 繁体：zh-Hant / zh-TW / zh-HK / zh-MO
            if first.contains("hant") || first.hasPrefix("zh-tw")
                || first.hasPrefix("zh-hk") || first.hasPrefix("zh-mo") {
                return .zhHant
            }
            return .zhHans
        }
        return .en
    }

    /// 测试与诊断用：某种语言下有多少条文案
    static func entryCount(_ lang: CopyLanguage) -> Int { table[lang]?.count ?? 0 }

    private static let table: [CopyLanguage: [String: String]] = {
        var result: [CopyLanguage: [String: String]] = [:]
        let sources: [(CopyLanguage, String)] = [
            (.zhHans, CopyTables.zhHansJSON),
            (.zhHant, CopyTables.zhHantJSON),
            (.en, CopyTables.enJSON),
        ]
        for (lang, json) in sources {
            guard let data = json.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            result[lang] = map
        }
        return result
    }()
}
