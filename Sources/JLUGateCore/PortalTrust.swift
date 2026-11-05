import Foundation

/// 网页认证登录页的可信判定。
///
/// 学校自己的门户 / 登录页都在 `*.jlu.edu.cn` 下（实测是 `login.jlu.edu.cn`）。
/// 这个判断只用来决定"要不要自动打开浏览器、面板上要不要拦一下"——**它不是安全边界**，
/// 真正的防线是：认准 Wi-Fi 名字（JLU.WIFI / JLU.PC）+ 看一眼浏览器地址栏。
///
/// 为什么不比对 SSID：macOS 10.15 起读当前 Wi-Fi 名字需要「定位」权限，没授权时
/// CoreWLAN / networksetup 都拿不到（`networksetup -getairportnetwork en0` 会直接
/// 回"未关联"），硬判只会把正常用户挡在门外。
public enum PortalTrust {
    /// 只认 `jlu.edu.cn` 及其子域。
    /// `eviljlu.edu.cn`、`jlu.edu.cn.example.com` 这类相似域名一律不算。
    public static func isSchoolHost(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty else { return false }
        return normalized == "jlu.edu.cn" || normalized.hasSuffix(".jlu.edu.cn")
    }

    public static func isTrusted(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        return isSchoolHost(host)
    }
}
