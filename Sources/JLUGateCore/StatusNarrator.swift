import Foundation

/// 状态的"人话"叙述：给新手看的标题 + 一句比喻 + 该做什么。
///
/// 为什么单独放 Core：这些文案是产品的一部分（用户第一眼看到的就是它），
/// 用单元测试锁住，避免以后改代码又把"UDP 被占用"这种内部术语丢给用户。
public enum StatusPhase: Sendable, Equatable {
    /// 还没配置 / 没开始
    case idle
    /// 正在识别、握手、认证
    case working
    /// 本程序维持的在线
    case online
    /// 官方 Dr.Com 客户端维持的在线（端口被它占着）
    case onlineViaOfficialClient
    /// 端口被官方客户端占着，但网没通
    case officialClientHoldingPort
    /// 其它失败
    case failed
    /// 网卡没插 / 没地址
    case waitingForNetwork
}

public struct StatusStory: Sendable, Equatable {
    public let title: String
    /// 一句人话（可以带比喻）
    public let oneLiner: String
    /// 需要用户做什么；不需要则为 nil
    public let action: String?
}

public enum StatusNarrator {
    public static func story(_ phase: StatusPhase) -> StatusStory {
        switch phase {
        case .idle:
            StatusStory(title: "还没连上",
                        oneLiner: "现在走的是「没认证」状态，就像进了校门但还没刷校园卡。",
                        action: "点下面的「连接」就会帮你刷一次。")

        case .working:
            StatusStory(title: "正在连…",
                        oneLiner: "正在跟学校网关核对身份，像门卫看一眼你的卡，通常一两秒。",
                        action: nil)

        case .online:
            StatusStory(title: "已连接",
                        oneLiner: "这条路是 JLU Gate 在替你守着，可以正常上网。",
                        action: nil)

        case .onlineViaOfficialClient:
            StatusStory(title: "已连接（官方客户端在管）",
                        oneLiner: "官方 Dr.Com 客户端正握着那条通道（它先占了端口），网络是通的，你也能上网。",
                        action: "想让 JLU Gate 接管：先在官方客户端里退出，再回来点「连接」。")

        case .officialClientHoldingPort:
            StatusStory(title: "官方客户端占着通道，但没连上",
                        oneLiner: "端口被官方客户端捏在手里，可它自己也没认证成功——像有人占了电话亭却没打通。",
                        action: "退出官方 Dr.Com 客户端（含菜单栏/后台的 DrClientNS），再点「连接」。")

        case .waitingForNetwork:
            StatusStory(title: "等网络就绪",
                        oneLiner: "电脑现在还没有可用的网线/IP，像车还没上高速。",
                        action: "插好网线（或确认这块网卡有地址），程序会自动继续。")

        case .failed:
            StatusStory(title: "没连上",
                        oneLiner: "尝试过了，但没通过网关这一关。",
                        action: "看下面的原因；改完点「重试」。")
        }
    }

    /// 把具体错误翻成"新手能懂的一句"。
    public static func explain(portHeldByOfficialClient: Bool,
                               linkIsWebPortal: Bool) -> String? {
        if portHeldByOfficialClient {
            return "学校客户端先占了认证用的「电话号码」（UDP 61440），我们打不进去。"
        }
        if linkIsWebPortal {
            return "网页认证走浏览器：登录页会在浏览器里打开，登录完回来点「已完成登录」。"
        }
        return nil
    }
}
