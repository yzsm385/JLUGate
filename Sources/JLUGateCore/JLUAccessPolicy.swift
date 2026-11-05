import Foundation

/// JLU 接入的硬规则（来自真机实测，2026-11-03）：
///
/// - **按 MAC 认设备**：账号与"一个 MAC"绑定，改登记才能换设备；
/// - 有线用 USB 网卡的 MAC，`JLU.PC` 用**本机 Wi-Fi 网卡**的 MAC —— 两者不是同一块卡；
/// - 所以"有线在这台、JLU.PC 在另一台"是行不通的：一台设备只有一块 Wi-Fi 网卡、一块网线口，
///   MAC 固定不可改（不是软件能改的）。
public enum JLUAccessPolicy {
    /// 线上自助平台（查询邮箱账号 / 办理入网 / 改登记 MAC）。
    public static let selfServiceURL = URL(string: "https://ip.jlu.edu.cn/pay")!

    /// MAC 不一致时的完整解释（比"MAC 不匹配"多三句人话）。
    public static func macMismatchHint(expected: String?, actual: String?,
                                       interfaceName: String? = nil) -> String {
        let want = expected ?? Copy.t("B401")
        let got = actual ?? Copy.t("B402")
        let iface = interfaceName.map { "（\($0)）" } ?? ""
        return Copy.f("B403", iface, got, want, got)
    }

    /// 当前用的 MAC 是"私有/随机地址"时的解释与处理建议。
    public static func privateMACHint(current: String, hardware: String?, registered: String?) -> String {
        let hardwareText = hardware ?? Copy.t("B404")
        let registeredText = registered ?? Copy.t("B405")
        return Copy.f("B406", current, hardwareText, registeredText)
    }

    /// JLU.PC 的前置说明（向导里展示）。
    public static let jluPCHint = Copy.t("B407")

    /// 连上 JLU.PC 时系统会弹一个"欢迎使用吉林大学校园网"的网页，这是**系统的门户页**，不是我们弹的。
    public static let captivePageNote = Copy.t("B408")

    /// 服务器原话归类为"MAC 不符"时补的一句。
    public static let rejectedByMacHint = Copy.t("B409")
}
