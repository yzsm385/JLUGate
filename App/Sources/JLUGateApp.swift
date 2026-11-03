import SwiftUI
import AppKit

/// 菜单栏常驻应用（`LSUIElement = YES`，纯 SwiftUI，Liquid Glass）。
@main
struct JLUGateApp: App {
    @State private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            Image(systemName: model.state.isOnline
                  ? "bolt.horizontal.circle.fill"
                  : (model.state.isBusy ? "circle.dotted" : model.statusSymbol))
                .symbolEffect(.pulse, isActive: model.state.isBusy)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
