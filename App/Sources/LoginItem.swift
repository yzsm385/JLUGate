import Foundation
import AppKit
import JLUGateCore
import ServiceManagement

/// 开机自启（`SMAppService.mainApp`）。失败只记日志，不阻断主功能。
enum LoginItem {
    static func apply(enabled: Bool) {
        guard AppIdentity.isInstalled else {
            FileLogger.shared.log("登录项：便携副本，跳过注册（放在 /Applications 才会自启）")
            return
        }
        let before = SMAppService.mainApp.status
        do {
            if enabled {
                if before != .enabled { try SMAppService.mainApp.register() }
            } else if before != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            let after = SMAppService.mainApp.status
            FileLogger.shared.log("登录项：\(enabled ? "开启" : "关闭")，状态 \(before.rawValue) → \(after.rawValue)")
        } catch {
            FileLogger.shared.log("登录项：\(enabled ? "注册" : "注销")失败（\(error.localizedDescription)），当前状态 \(SMAppService.mainApp.status.rawValue)")
        }
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// 是否已经能在开机后自动起来
    static var isEnabled: Bool {
        AppIdentity.isInstalled && SMAppService.mainApp.status == .enabled
    }

    /// 给界面用的一句话状态
    static var statusText: String {
        guard AppIdentity.isInstalled else { return Copy.t("R23") }
        switch SMAppService.mainApp.status {
        case .enabled: return Copy.t("R20")
        case .requiresApproval: return Copy.t("R22")
        case .notRegistered, .notFound: return Copy.t("R21")
        @unknown default: return Copy.t("R21")
        }
    }

    /// 跳到「系统设置 → 通用 → 登录项与扩展」
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    /// 现在就试着登记一次（已登记则只跳设置）
    static func enableNow() {
        apply(enabled: true)
        openSystemSettings()
    }
}
