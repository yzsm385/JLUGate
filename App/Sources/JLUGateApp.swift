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

    /// 在访达里双击已在运行的 App：系统不会重新启动进程，只会发 reopen。
    /// 用户此时想要的通常是"看到界面"，所以先亮面板，再顺手触发一次连接。
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        FileLogger.shared.log("访达再次打开 App：弹出面板")
        showPanel()
        if let model, !model.state.isOnline, !model.state.isBusy {
            FileLogger.shared.log("访达再次打开 App：触发自动连接")
            model.retry()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileLogger.shared.log("启动：进程已起来（bundle=\(Bundle.main.bundleURL.path)，"
                              + "installed=\(AppIdentity.isInstalled)）")
        CrashReporter.install()
        NSApplication.shared.setActivationPolicy(.accessory)

        // 先把菜单栏图标挂上，再做后面的初始化：初始化再慢，用户也能看到"App 起来了"，
        // 不会双击半天以为没反应；日志也能区分"没启动"和"卡在初始化"。
        buildStatusItem()
        FileLogger.shared.log("启动：菜单栏图标已就绪")

        _ = SingleInstance.claim { NSApp.terminate(nil) }

        buildMainMenu()
        AppIdentity.migrateIfNeeded()
        terminateOtherCopies()
        let model = AppModel()
        self.model = model
        observeIcon(model: model)
        FileLogger.shared.log("启动：初始化完成")

        if let start = DevOverrides.startPanelName, let panel = Self.panel(named: start) {
            model.show(panel)
        }
        if DevOverrides.openPanelOnLaunch || CommandLine.arguments.contains("--open-panel") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                self.showPanel()
            }
        }

        // 用户手动打开（不是登录项拉起）：等状态栏图标真正就位后把面板亮出来。
        // showPanel() 自己会确认锚点已经进菜单栏，所以这里 400ms 后调用不会放歪。
        let launchedByUser = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        FileLogger.shared.log("启动：launchedByUser=\(launchedByUser)")
        if launchedByUser,
           DevOverrides.startPanelName == nil,
           !DevOverrides.openPanelOnLaunch,
           !CommandLine.arguments.contains("--open-panel"),
           !DevOverrides.autostart {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
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

    private func buildStatusItem() {
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
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var lastIconName: String?

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
        guard name != lastIconName else { return }   // 没变化就别重建 NSImage
        lastIconName = name
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
        // 只结束"同类"副本：正式版清正式版，便携版不动别人
        guard AppIdentity.isInstalled, let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == bundleID && app.processIdentifier != current
            && AppIdentity.sameKind(as: app.bundleURL ?? URL(fileURLWithPath: "/")) {
            FileLogger.shared.log("发现另一份 JLU Gate（pid \(app.processIdentifier)），正在结束它")
            app.terminate()
        }
    }

    /// 显示菜单栏面板。
    ///
    /// 真机踩过的坑（macOS 14）：启动阶段就 show 的话，状态栏按钮的窗口可能还停在
    /// 屏幕原点、没被系统摆到菜单栏右上角；NSPopover 会按那个坐标锚定，于是整个
    /// 面板飘到屏幕左上角（压在访达上），而且会一直停在那儿。
    /// 所以先确认按钮真的进了菜单栏区域（窗口在屏幕上半部），再激活 App 并显示；
    /// 不满足就隔 300ms 重试，最多 10 次。
    func showPanel(retry: Int = 0) {
        guard let model, let button = statusItem?.button else { return }

        // 状态栏按钮刚建出来时，窗口可能还停在菜单栏最左边、没被系统排到右上角；
        // 这时 show，NSPopover 就锚在左边——真机现象是面板跑到屏幕左上、压在访达上。
        // 所以要求锚点既在屏幕上半部、又在右半边，否则 300ms 后重试。
        guard let window = button.window else {
            guard retry < 10 else {
                FileLogger.shared.log("面板：状态栏按钮一直不在窗口里，放弃显示")
                return
            }
            retryPanelShow(retry)
            return
        }
        let placed = window.screen.map {
            window.frame.minY > $0.frame.midY && window.frame.minX > $0.frame.midX
        } ?? false
        if !placed, retry < 10 {
            FileLogger.shared.log("面板：按钮还没摆到菜单栏右侧（x=\(window.frame.minX) y=\(window.frame.minY)），300ms 后重试（\(retry + 1)/10）")
            retryPanelShow(retry)
            return
        }
        if !placed {
            FileLogger.shared.log("面板：锚点一直异常，按当前坐标显示（可能放歪）")
        }

        // 先激活再 show：非活跃的 accessory App 在 macOS 14 上也会把 popover 放歪
        NSApp.activate(ignoringOtherApps: true)

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

        // 之前可能在错误位置显示过：先收起，再按当前锚点重新显示
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.isPanelVisible = true
        FileLogger.shared.log("面板：已显示（锚点 x=\(window.frame.minX) y=\(window.frame.minY)，屏幕宽 \(window.screen?.frame.width ?? 0)）")
    }

    private func retryPanelShow(_ retry: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.showPanel(retry: retry + 1)
        }
    }

    func closePanel() {
        popover?.performClose(nil)
        model?.isPanelVisible = false
    }
}
