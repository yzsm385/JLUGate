import Foundation

/// 校园网门户/欢迎页相关的固定信息。
///
/// 背景（实测 2026-11-03）：连上 JLU.PC 后，**系统**会弹 `login.jlu.edu.cn` 的欢迎页，
/// 里面是校园网使用说明 + 广告。这个弹窗不是本程序弹的，也关不掉——
/// 但我们可以把那个页面**收进来**，做成 App 内可点开的"校园网门户"。
public enum PortalAssets {
    /// 系统弹窗是"捕获门户助手"（Captive Network Assistant）的行为。
    public static let systemPopupNote = Copy.t("B413")

    /// 想彻底关掉系统自动弹窗，需要管理员执行（会影响所有需要登录的网络）。
    public static let disableCaptiveAssistantCommand =
        "sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false"

    /// 恢复默认。
    public static let enableCaptiveAssistantCommand =
        "sudo defaults delete /Library/Preferences/SystemConfiguration/com.apple.captive.control Active"

    /// 门户缓存文件名（HTML 原样保存，供离线查看）。
    public static let cacheFileName = "portal-page.html"
}
