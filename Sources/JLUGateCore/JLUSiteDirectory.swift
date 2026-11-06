import Foundation

/// 吉大常用站点合集：把"每次都要去收藏夹翻"的入口收进 App。
///
/// 分三类访问范围：
/// - `.publicSite`：校内外都能打开
/// - `.campusOnly`：只在校园网内能打开（校外要先连 WebVPN）
/// - `.vpnPreferred`：页面本身公开，但里面的资源（数据库、办事流程）要校园网/WebVPN
public struct JLUSite: Sendable, Equatable, Identifiable, Hashable {
    public enum Access: String, Sendable, Equatable {
        case publicSite = "公网"
        case campusOnly = "仅校内"
        case vpnPreferred = "需 VPN"

        /// 界面显示用的本地化名字（rawValue 只作内部标识）
        public var displayName: String {
            switch self {
            case .publicSite: Copy.t("TD01")
            case .campusOnly: Copy.t("TD02")
            case .vpnPreferred: Copy.t("TD03")
            }
        }
    }

    public enum Category: String, Sendable, CaseIterable {
        case study = "学习与教务"
        case office = "办事与校务"
        case mail = "邮箱"
        case network = "校园网"
        case info = "资讯与官网"

        public var displayName: String {
            switch self {
            case .study: Copy.t("TD04")
            case .office: Copy.t("TD05")
            case .mail: Copy.t("TD06")
            case .network: Copy.t("TD07")
            case .info: Copy.t("TD08")
            }
        }
    }

    public let title: String
    public let host: String
    public let category: Category
    public let access: Access
    /// 一句话说明它用来干什么
    public let note: String
    /// 是否支持"复制账号/密码"辅助登录
    public let supportsCredentialPrefill: Bool
    /// http / https（个别学校站点只有 http）
    public let scheme: String
    /// 域名后面的路径（比如 zhxg 的 `/xg/`、第二课堂的 `/jlu-2c/`）
    public let path: String

    public init(title: String, host: String, category: Category, access: Access,
                note: String, supportsCredentialPrefill: Bool,
                scheme: String = "https", path: String = "") {
        self.title = title
        self.host = host
        self.category = category
        self.access = access
        self.note = note
        self.supportsCredentialPrefill = supportsCredentialPrefill
        self.scheme = scheme
        self.path = path
    }

    public var id: String { host }
    public var url: URL? {
        let suffix = path.isEmpty ? "" : "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(scheme)://\(host)\(suffix)/")
    }
    public var isCampusRelevant: Bool { access != .publicSite }
}

public enum JLUSiteDirectory {
    public static let all: [JLUSite] = [
        // 学习与教务
        .init(title: Copy.t("TD09"), host: "iedu.jlu.edu.cn", category: .study,
              access: .campusOnly, note: Copy.t("TD10"), supportsCredentialPrefill: true),
        .init(title: Copy.t("TD11"), host: "jwc.jlu.edu.cn", category: .study,
              access: .publicSite, note: Copy.t("TD12"), supportsCredentialPrefill: false),
        .init(title: Copy.t("TD13"), host: "yjsy.jlu.edu.cn", category: .study,
              access: .publicSite, note: Copy.t("TD14"), supportsCredentialPrefill: false),
        .init(title: Copy.t("TD15"), host: "lib.jlu.edu.cn", category: .study,
              access: .vpnPreferred, note: Copy.t("TD16"), supportsCredentialPrefill: false),

        // 办事与校务
        .init(title: Copy.t("TD17"), host: "oa.jlu.edu.cn", category: .office,
              access: .campusOnly, note: Copy.t("TD18"), supportsCredentialPrefill: true),
        .init(title: Copy.t("TD19"), host: "ehall.jlu.edu.cn", category: .office,
              access: .campusOnly, note: Copy.t("TD20"), supportsCredentialPrefill: true),
        .init(title: Copy.t("TD21"), host: "cas.jlu.edu.cn", category: .office,
              access: .campusOnly, note: Copy.t("TD22"), supportsCredentialPrefill: true),

        // 邮箱
        .init(title: Copy.t("TD23"), host: "mails.jlu.edu.cn", category: .mail,
              access: .publicSite, note: Copy.t("TD24"), supportsCredentialPrefill: true),
        .init(title: Copy.t("TD25"), host: "mail.jlu.edu.cn", category: .mail,
              access: .publicSite, note: Copy.t("TD26"), supportsCredentialPrefill: true),

        // 校园网
        .init(title: "WebVPN", host: "vpn.jlu.edu.cn", category: .network,
              access: .publicSite, note: Copy.t("TD27"), supportsCredentialPrefill: true),
        // 这个平台用的是**校园卡号 + 6 位 V 卡密码**，和统一账号不是一套，
        // 所以不能预填（复制过去的账号反而会让人以为密码错了）。
        .init(title: Copy.t("TD28"), host: "ip.jlu.edu.cn", category: .network,
              access: .campusOnly,
              note: Copy.t("TD29"),
              supportsCredentialPrefill: false),
        .init(title: Copy.t("TD30"), host: "nic.jlu.edu.cn", category: .network,
              access: .publicSite, note: Copy.t("TD31"), supportsCredentialPrefill: false),

        // 资讯与官网
        .init(title: Copy.t("TD32"), host: "www.jlu.edu.cn", category: .info,
              access: .publicSite, note: Copy.t("TD33"), supportsCredentialPrefill: false),
        .init(title: Copy.t("TD34"), host: "news.jlu.edu.cn", category: .info,
              access: .publicSite, note: Copy.t("TD35"), supportsCredentialPrefill: false),

        // 学习与教务：选课 / 二课堂 / 考试报名
        .init(title: Copy.t("TD36"), host: "icourses.jlu.edu.cn", category: .study,
              access: .campusOnly, note: Copy.t("TD37"), supportsCredentialPrefill: true),
        .init(title: Copy.t("TD48"), host: "classroom.univteam.com", category: .study,
              access: .publicSite, note: Copy.t("TD49"), supportsCredentialPrefill: false,
              path: "jlu-2c"),
        .init(title: Copy.t("TD42"), host: "registry.jlu.edu.cn", category: .study,
              access: .publicSite, note: Copy.t("TD43"), supportsCredentialPrefill: false,
              scheme: "http"),
        .init(title: Copy.t("TD44"), host: "kszx.jlu.edu.cn", category: .study,
              access: .publicSite, note: Copy.t("TD45"), supportsCredentialPrefill: false,
              scheme: "http"),
        .init(title: Copy.t("TD50"), host: "cet-bm.neea.edu.cn", category: .study,
              access: .publicSite, note: Copy.t("TD51"), supportsCredentialPrefill: false,
              scheme: "http"),
        .init(title: Copy.t("TD52"), host: "www.chinaneccs.cn", category: .study,
              access: .publicSite, note: Copy.t("TD53"), supportsCredentialPrefill: false,
              scheme: "http"),

        // 办事与校务：智慧学工 / 校园卡 / 缴费 / 学工部
        .init(title: Copy.t("TD38"), host: "zhxg.jlu.edu.cn", category: .office,
              access: .campusOnly, note: Copy.t("TD39"), supportsCredentialPrefill: true,
              path: "xg"),
        .init(title: Copy.t("TD40"), host: "dsf.jlu.edu.cn", category: .office,
              access: .campusOnly, note: Copy.t("TD41"), supportsCredentialPrefill: true,
              scheme: "http"),
        .init(title: Copy.t("TD54"), host: "cwsf.jlu.edu.cn", category: .office,
              access: .publicSite, note: Copy.t("TD55"), supportsCredentialPrefill: true,
              scheme: "http"),
        .init(title: Copy.t("TD46"), host: "xsc.jlu.edu.cn", category: .office,
              access: .publicSite, note: Copy.t("TD47"), supportsCredentialPrefill: false,
              scheme: "http"),
    ]

    public static func sites(in category: JLUSite.Category) -> [JLUSite] {
        all.filter { $0.category == category }
    }

    /// 说明：邮箱确实校内外都能开，所以它不是"校内独有"的证据。
    public static var campusOnlyHosts: Set<String> {
        Set(all.filter { $0.access == .campusOnly }.map(\.host))
    }
}
