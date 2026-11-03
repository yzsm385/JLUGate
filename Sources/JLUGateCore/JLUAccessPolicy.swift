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
        let want = expected ?? "未登记"
        let got = actual ?? "未知"
        let iface = interfaceName.map { "（\($0)）" } ?? ""
        return """
        学校按 **MAC 地址** 认设备：当前网卡\(iface) 是 \(got)，而账号登记的是 \(want)。
        有线走的是网线/USB 网卡的 MAC，JLU.PC 走的是 Wi-Fi 网卡的 MAC，两者不是同一块卡、也不能互改。
        要改用这个网络，得先到自助平台把登记 MAC 改成 \(got)（改了以后原来那台就用不了了）。
        """
    }

    /// JLU.PC 的前置说明（向导里展示）。
    public static let jluPCHint = """
    JLU.PC 使用本机 **Wi-Fi 网卡** 的 MAC 认证。若你在学校登记的是 USB/有线网卡的 MAC，
    这里会认证失败——需要先到 ip.jlu.edu.cn 把登记 MAC 改成 Wi-Fi 网卡的（改完有线那台会失效）。
    """

    /// 连上 JLU.PC 时系统会弹一个"欢迎使用吉林大学校园网"的网页，这是**系统的门户页**，不是我们弹的。
    public static let captivePageNote = """
    连上 JLU.PC 后系统会弹一个 login.jlu.edu.cn 的欢迎页，这是校园网的门户页（正常现象）。
    关掉即可：认证由本程序完成，不需要在那个页面里下载官方客户端。
    """

    /// 服务器原话归类为"MAC 不符"时补的一句。
    public static let rejectedByMacHint = """
    服务器认为这个 MAC 不属于你的账号。Mac 的 MAC 是网卡固化的，不能靠软件改：
    请到 ip.jlu.edu.cn 核对/修改登记 MAC，或换回登记过的那块网卡。
    """
}
