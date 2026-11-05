import Foundation
import JLUGateCore
import ServiceManagement

/// 开机自启（`SMAppService.mainApp`）。失败只记日志，不阻断主功能。
enum LoginItem {
    static func apply(enabled: Bool) {
        guard AppIdentity.isInstalled else {
            NSLog(Copy.t("N25"))
            return
        }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog(Copy.f("N26", error.localizedDescription))
        }
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
