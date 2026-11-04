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

        buildMainMenu()
        terminateOtherCopies()
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
        case "inspect": .inspect
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// 菜单栏右键菜单：不打开面板也能操作
    private func showContextMenu() {
        guard let model, let button = statusItem?.button else { return }
        let menu = NSMenu()
        let toggle = model.state.isOnline
            ? NSMenuItem(title: "断开连接", action: #selector(disconnectFromMenu), keyEquivalent: "")
            : NSMenuItem(title: "立即连接", action: #selector(connectFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let status = NSMenuItem(title: "刷新状态", action: #selector(refreshFromMenu), keyEquivalent: "")
        status.target = self
        menu.addItem(status)
        let inspect = NSMenuItem(title: "网络体检", action: #selector(inspectFromMenu), keyEquivalent: "")
        inspect.target = self
        menu.addItem(inspect)
        let settings = NSMenuItem(title: "设置…", action: #selector(settingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 JLU Gate", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        // 直接把菜单弹在按钮下方：比"临时挂 menu + performClick"可靠
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func connectFromMenu() { model?.retry() }
    @objc private func disconnectFromMenu() { model?.disconnect() }
    @objc private func refreshFromMenu() { model?.refreshDiagnostics() }
    @objc private func inspectFromMenu() { model?.show(.inspect) }
    @objc private func settingsFromMenu() { model?.presentSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

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
        // 右键：弹菜单（连接/断开、体检、设置、退出）
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPanel()
        }
    }

    /// 给 LSUIElement 也能用 ⌘Q 退出（菜单栏图标失灵时的兜底）
    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 JLU Gate", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 JLU Gate", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    /// 同 bundle id 的旧副本（例如 /Applications 里那份）会抢同一个状态栏图标，
    /// 导致"点了没反应"。启动时把它们关掉，只留当前这份。
    private func terminateOtherCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == bundleID && app.processIdentifier != current {
            FileLogger.shared.log("发现另一份 JLU Gate（pid \(app.processIdentifier)），正在结束它")
            app.terminate()
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
        guard button.window != nil else {
            // 刚登录/刚重启时状态栏按钮可能还没进窗口：稍后再试一次，而不是静默失败
            FileLogger.shared.log("面板：按钮还不在窗口里，稍后重试")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard let button = self.statusItem?.button, button.window != nil else { return }
                self.popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        FileLogger.shared.log("面板：已显示")
    }

    func closePanel() {
        popover?.performClose(nil)
    }
}
