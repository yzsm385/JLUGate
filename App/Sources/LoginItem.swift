import Foundation
import ServiceManagement

/// 开机自启（`SMAppService.mainApp`）。失败只记日志，不阻断主功能。
enum LoginItem {
    static func apply(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("JLUGate: 登录项设置失败 \(error.localizedDescription)")
        }
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
