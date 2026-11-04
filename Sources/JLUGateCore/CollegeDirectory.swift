import Foundation

/// 吉大各学院/学部的官网目录。
///
/// 数据来源：吉林大学官网「院系设置」页 `www.jlu.edu.cn/jgsz/yxsz.htm`（逐个抓取，含页面标题核对）。
/// 学号 → 学院：吉大官方没有公开的"学院代码对照表"，所以这里**不编造映射**，
/// 而是用"学号前缀学习"：第一次由你选一次学院，之后同一前缀（4 位入学年份 + 2 位学院码）
/// 就自动认出来；前缀规则保存在本机，不上传。
public struct College: Sendable, Equatable, Identifiable, Hashable {
    public let name: String
    public let host: String

    public var id: String { host }
    public var url: URL? { URL(string: "https://\(host)/") }

    public init(name: String, host: String) {
        self.name = name
        self.host = host
    }
}

public enum CollegeDirectory {
    /// 官方院系设置页列出的学院（按页面顺序，去掉非学院条目）。
    public static let all: [College] = [
        College(name: "哲学社会学院", host: "zsy.jlu.edu.cn"),
        College(name: "文学院", host: "wxy.jlu.edu.cn"),
        College(name: "考古学院", host: "kgxy.jlu.edu.cn"),
        College(name: "历史文化学院", host: "hac.jlu.edu.cn"),
        College(name: "外国语言文化学院", host: "sflc.jlu.edu.cn"),
        College(name: "艺术学院", host: "art.jlu.edu.cn"),
        College(name: "体育学院", host: "pe.jlu.edu.cn"),
        College(name: "经济学院", host: "jjxy.jlu.edu.cn"),
        College(name: "法学院", host: "law.jlu.edu.cn"),
        College(name: "行政学院", host: "adm.jlu.edu.cn"),
        College(name: "商学与管理学院", host: "sg.jlu.edu.cn"),
        College(name: "马克思主义学院", host: "marx.jlu.edu.cn"),
        College(name: "东北亚学院", host: "nasa.jlu.edu.cn"),
        College(name: "公共外交学院", host: "sipa.jlu.edu.cn"),
        College(name: "数学学院", host: "math.jlu.edu.cn"),
        College(name: "物理学院", host: "phy.jlu.edu.cn"),
        College(name: "化学学院", host: "chem.jlu.edu.cn"),
        College(name: "生命科学学院", host: "life.jlu.edu.cn"),
        College(name: "机械与航空航天工程学院", host: "mae.jlu.edu.cn"),
        College(name: "汽车工程学院", host: "auto.jlu.edu.cn"),
        College(name: "材料科学与工程学院", host: "dmse.jlu.edu.cn"),
        College(name: "交通学院", host: "jt.jlu.edu.cn"),
        College(name: "生物与农业工程学院", host: "cbae.jlu.edu.cn"),
        College(name: "卓越工程师学院", host: "ees.jlu.edu.cn"),
        College(name: "电子科学与工程学院", host: "ee.jlu.edu.cn"),
        College(name: "通信工程学院", host: "dce.jlu.edu.cn"),
        College(name: "计算机科学与技术学院", host: "ccst.jlu.edu.cn"),
        College(name: "软件学院", host: "csw.jlu.edu.cn"),
        College(name: "地球科学学院", host: "geo.jlu.edu.cn"),
        College(name: "地球探测科学与技术学院", host: "gest.jlu.edu.cn"),
        College(name: "建设工程学院", host: "const.jlu.edu.cn"),
        College(name: "新能源与环境学院", host: "cer.jlu.edu.cn"),
        College(name: "仪器科学与电气工程学院", host: "ciee.jlu.edu.cn"),
        College(name: "基础医学院", host: "medicine.jlu.edu.cn"),
        College(name: "公共卫生学院", host: "sph.jlu.edu.cn"),
        College(name: "药学院", host: "yxy.jlu.edu.cn"),
        College(name: "护理学院", host: "hlxy.jlu.edu.cn"),
        College(name: "白求恩口腔医学院", host: "jdkq.jlu.edu.cn"),
        College(name: "动物医学学院", host: "dwyx.jlu.edu.cn"),
        College(name: "植物科学学院", host: "zky.jlu.edu.cn"),
        College(name: "动物科学学院", host: "dwkx.jlu.edu.cn"),
        College(name: "食品科学与工程学院", host: "spxy.jlu.edu.cn"),
        College(name: "人工智能学院", host: "sai.jlu.edu.cn"),
        College(name: "国际语言学院", host: "gjyyxy.jlu.edu.cn"),
    ]

    public static func college(forHost host: String) -> College? {
        all.first { $0.host == host }
    }

    public static func search(_ keyword: String) -> [College] {
        guard !keyword.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.host.localizedCaseInsensitiveContains(keyword)
        }
    }
}
