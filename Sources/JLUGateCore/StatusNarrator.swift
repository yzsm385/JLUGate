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
    /// 会话还在，但外网探针连续不通：大概率是被代理的全局模式截住了
    case sessionOnly
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
            StatusStory(title: Copy.t("B101"),
                        oneLiner: Copy.t("B102"),
                        action: Copy.t("B103"))

        case .working:
            StatusStory(title: Copy.t("B104"),
                        oneLiner: Copy.t("B105"),
                        action: nil)

        case .online:
            StatusStory(title: Copy.t("B106"),
                        oneLiner: Copy.t("B107"),
                        action: nil)

        case .sessionOnly:
            StatusStory(title: Copy.t("B162"),
                        oneLiner: Copy.t("B163"),
                        action: Copy.t("B164"))

        case .onlineViaOfficialClient:
            StatusStory(title: Copy.t("B108"),
                        oneLiner: Copy.t("B109"),
                        action: Copy.t("B110"))

        case .officialClientHoldingPort:
            StatusStory(title: Copy.t("B111"),
                        oneLiner: Copy.t("B112"),
                        action: Copy.t("B113"))

        case .waitingForNetwork:
            StatusStory(title: Copy.t("B114"),
                        oneLiner: Copy.t("B115"),
                        action: Copy.t("B116"))

        case .failed:
            StatusStory(title: Copy.t("B117"),
                        oneLiner: Copy.t("B118"),
                        action: Copy.t("B119"))
        }
    }

    /// 把具体错误翻成"新手能懂的一句"。
    public static func explain(portHeldByOfficialClient: Bool,
                               linkIsWebPortal: Bool) -> String? {
        if portHeldByOfficialClient {
            return Copy.t("B120")
        }
        if linkIsWebPortal {
            return Copy.t("B121")
        }
        return nil
    }
}
