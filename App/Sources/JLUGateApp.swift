import SwiftUI
import AppKit

/// 菜单栏常驻应用（`LSUIElement = YES`，纯 SwiftUI，Liquid Glass）。
@main
struct JLUGateApp: App {
    @State private var model = AppModel()

    init() {
        CrashReporter.install()          // 先装崩溃兜底，越早越好
        NSApplication.shared.setActivationPolicy(.accessory)
        // 单实例：已经有实例在跑就激活它并退出自己（端口 61440 不能有两个主人）
        _ = SingleInstance.claim { NSApp.terminate(nil) }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
                .environment(\.glassAllowed, true)   // 只有菜单栏面板用液态玻璃
        } label: {
            Image(systemName: model.state.isOnline
                  ? "bolt.horizontal.circle.fill"
                  : (model.state.isBusy ? "circle.dotted" : model.statusSymbol))
                .symbolEffect(.pulse, isActive: model.state.isBusy)
        }
        .menuBarExtraStyle(.window)

    }
}
