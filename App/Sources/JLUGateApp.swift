import SwiftUI
import AppKit

/// 菜单栏常驻应用（`LSUIElement = YES`）。
///
/// 为什么不用 `MenuBarExtra`：它的面板是系统私有的 `NSStatusBarWindow`，
/// 里面的 SwiftUI 布局一旦超尺寸抛异常就是 SIGABRT，且**无法在本地打开来验证**。
/// 改成自己持有 `NSStatusItem + NSPopover`：
/// - 有明确的窗口与尺寸，可以设 `contentSize`、可以截图验证；
/// - 出问题还能在开发机上用 `--open-panel` 直接打开面板看。
@main
struct JLUGateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 占位场景：真正的界面由 AppDelegate 的菜单项 + popover 承载
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var iconTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.install()
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = SingleInstance.claim { NSApp.terminate(nil) }

        let model = AppModel()
        self.model = model
        buildStatusItem(model: model)
        observeIcon(model: model)

        if let start = DevOverrides.startPanelName, let panel = Self.panel(named: start) {
            model.show(panel)
        }
        if DevOverrides.openPanelOnLaunch || CommandLine.arguments.contains("--open-panel") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                self.showPanel()
            }
        }
    }

    static func panel(named name: String) -> AppModel.Panel? {
        switch name {
        case "settings": .settings
        case "wizard": .wizard
        case "detail": .detail
        case "status": .status
        case "portal": .portal
        default: nil
        }
    }

    // MARK: 菜单栏图标

    private func buildStatusItem(model: AppModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "shield.lefthalf.filled",
                                   accessibilityDescription: "JLU Gate")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
    }

    private func observeIcon(model: AppModel) {
        iconTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateIcon(model: model)
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func updateIcon(model: AppModel) {
        guard let button = statusItem?.button else { return }
        let name: String
        if model.state.isOnline {
            name = "bolt.horizontal.circle.fill"
        } else if model.state.isBusy {
            name = "circle.dotted"
        } else {
            name = model.statusSymbol
        }
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "JLU Gate")
        button.image?.isTemplate = true
    }

    // MARK: 面板

    @objc private func togglePanel(_ sender: Any?) {
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let model, let button = statusItem?.button else { return }
        if popover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            // 面板内不使用液态玻璃：无法本地验证的渲染路径一律不上
            let root = MenuContent()
                .environment(model)
                .environment(\.glassAllowed, false)
            let controller = NSHostingController(rootView: root)
            controller.view.frame = NSRect(x: 0, y: 0, width: 380, height: 560)
            popover.contentViewController = controller
            popover.contentSize = NSSize(width: 380, height: 560)
            self.popover = popover
            FileLogger.shared.log("面板：已创建 NSPopover（380×560）")
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        FileLogger.shared.log("面板：已显示")
    }

    func closePanel() {
        popover?.performClose(nil)
    }
}
