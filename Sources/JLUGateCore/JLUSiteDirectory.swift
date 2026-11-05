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
    }

    public enum Category: String, Sendable, CaseIterable {
        case study = "学习与教务"
        case office = "办事与校务"
        case mail = "邮箱"
        case network = "校园网"
        case info = "资讯与官网"
    }

    public let title: String
    public let host: String
    public let category: Category
    public let access: Access
    /// 一句话说明它用来干什么
    public let note: String
    /// 是否支持"复制账号/密码"辅助登录
    public let supportsCredentialPrefill: Bool

    public var id: String { host }
    public var url: URL? { URL(string: "https://\(host)/") }
    public var isCampusRelevant: Bool { access != .publicSite }
}

public enum JLUSiteDirectory {
    public static let all: [JLUSite] = [
        // 学习与教务
        .init(title: "智慧校园（教务）", host: "iedu.jlu.edu.cn", category: .study,
              access: .campusOnly, note: "选课、课表、成绩、考试安排", supportsCredentialPrefill: true),
        .init(title: "本科生院", host: "jwc.jlu.edu.cn", category: .study,
              access: .publicSite, note: "教学通知、培养方案、学籍文件", supportsCredentialPrefill: false),
        .init(title: "研究生院", host: "yjsy.jlu.edu.cn", category: .study,
              access: .publicSite, note: "研究生培养、学位与招生通知", supportsCredentialPrefill: false),
        .init(title: "图书馆", host: "lib.jlu.edu.cn", category: .study,
              access: .vpnPreferred, note: "借阅查询、数据库入口（数据库需校内/VPN）", supportsCredentialPrefill: false),

        // 办事与校务
        .init(title: "电子校务平台（OA）", host: "oa.jlu.edu.cn", category: .office,
              access: .campusOnly, note: "公文、审批、通知与流程", supportsCredentialPrefill: true),
        .init(title: "一站式办事大厅", host: "ehall.jlu.edu.cn", category: .office,
              access: .campusOnly, note: "各类线上办事与申请", supportsCredentialPrefill: true),
        .init(title: "统一身份认证", host: "cas.jlu.edu.cn", category: .office,
              access: .campusOnly, note: "全校系统的登录入口（改密码也在这里）", supportsCredentialPrefill: true),

        // 邮箱
        .init(title: "学生邮箱", host: "mails.jlu.edu.cn", category: .mail,
              access: .publicSite, note: "学号/校园账号邮箱，校内外都能开", supportsCredentialPrefill: true),
        .init(title: "教师邮箱", host: "mail.jlu.edu.cn", category: .mail,
              access: .publicSite, note: "教职工邮件系统", supportsCredentialPrefill: true),

        // 校园网
        .init(title: "WebVPN", host: "vpn.jlu.edu.cn", category: .network,
              access: .publicSite, note: "校外访问校内系统的入口（统一身份认证登录）", supportsCredentialPrefill: true),
        // 这个平台用的是**校园卡号 + 6 位 V 卡密码**，和统一账号不是一套，
        // 所以不能预填（复制过去的账号反而会让人以为密码错了）。
        .init(title: "校园网自助服务", host: "ip.jlu.edu.cn", category: .network,
              access: .campusOnly,
              note: "查固定 IP / 登记 MAC、开户与充值（账号是校园卡号，密码是 6 位 V 卡密码）",
              supportsCredentialPrefill: false),
        .init(title: "大数据和网络管理中心", host: "nic.jlu.edu.cn", category: .network,
              access: .publicSite, note: "断网通知、服务指南、报修电话", supportsCredentialPrefill: false),

        // 资讯与官网
        .init(title: "吉林大学主页", host: "www.jlu.edu.cn", category: .info,
              access: .publicSite, note: "学校要闻与机构导航", supportsCredentialPrefill: false),
        .init(title: "新闻中心", host: "news.jlu.edu.cn", category: .info,
              access: .publicSite, note: "校内新闻与公告", supportsCredentialPrefill: false),
    ]

    public static func sites(in category: JLUSite.Category) -> [JLUSite] {
        all.filter { $0.category == category }
    }

    /// 说明：邮箱确实校内外都能开，所以它不是"校内独有"的证据。
    public static var campusOnlyHosts: Set<String> {
        Set(all.filter { $0.access == .campusOnly }.map(\.host))
    }
}
