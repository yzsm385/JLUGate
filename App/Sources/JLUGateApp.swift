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

    // MARK: 菜单栏图标位置（macOS 14 的坑）

    /// AppKit 自己用来记住"这枚图标排第几"的偏好键：`NSStatusItem Preferred Position <autosaveName>`。
    /// 值越小越靠右（300 大约就是其他菜单栏 App 那一排），0/巨大值会被排到最左边。
    private static let preferredPositionPrefix = "NSStatusItem Preferred Position "
    /// 当前这枚图标使用的 autosaveName：重建时换新名字，系统才会重新读取位置偏好。
    private static let autosaveNameKey = "JLUGate.statusItem.autosaveName"
    /// 重建代次。AppKit 会按 autosaveName 缓存图标位置，同一个名字重建不会生效，
    /// 所以每次重排都必须用一个从没用过的名字（JLUGate.g1、g2……）。
    private static let autosaveGenerationKey = "JLUGate.statusItem.generation"

    /// macOS 14 真机：状态栏图标会被系统摆到"紧挨着帮助"的位置，甚至压进 App 菜单中间
    /// （实测 x≈180/450，1280 宽的屏），而且之后再也不归位——面板跟着锚在左边。
    /// 所以不能听天由命：图标建好后量一次真实坐标，不在屏幕右半边就换名重建，
    /// 并显式写入位置偏好，把图标排到屏幕右侧。
    private let placementValues: [Double] = [300, 120]
    private var placementAttempt = 0
    private var placementProbeCount = 0
    private var baselineIconX: CGFloat?
    private var devHealUsed = false

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

        // 用户手动打开（不是登录项拉起）：等图标真正排到右侧、面板能贴住它之后再亮出来。
        // 1.5s 里包含了 checkStatusItemPlacement() 的第一次测量（1.0s）和必要时的重建。
        let launchedByUser = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        FileLogger.shared.log("启动：launchedByUser=\(launchedByUser)")
        if launchedByUser,
           DevOverrides.startPanelName == nil,
           !DevOverrides.openPanelOnLaunch,
           !CommandLine.arguments.contains("--open-panel"),
           !DevOverrides.autostart {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
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
        let name = UserDefaults.standard.string(forKey: Self.autosaveNameKey) ?? "JLUGate"
        createStatusItem(autosaveName: name)
        schedulePlacementCheck(after: .milliseconds(1000))
    }

    @discardableResult
    private func createStatusItem(autosaveName name: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        if let button = item.button {
            // 初始也用圆圈系（在线是"圆圈+闪电"），不要盾牌
            setStatusImage("circle.dashed", on: button)
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        lastIconName = nil                 // 新按钮还没有图标，让 observeIcon 下一轮补上
        UserDefaults.standard.set(name, forKey: Self.autosaveNameKey)
        FileLogger.shared.log("图标：已挂上（autosave=\(name)）")
        return item
    }

    /// 设置菜单栏图标。符号取不到（老系统缺某个 SF Symbol）时退回文字，
    /// 绝不能让图标变成 0 宽度——那样用户会以为"程序根本没起来"。
    private func setStatusImage(_ name: String, on button: NSStatusBarButton) {
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "JLU Gate") {
            button.image = image
            button.image?.isTemplate = true
            button.title = ""
        } else {
            button.image = nil
            button.title = "JLU"
            FileLogger.shared.log("图标：符号 \(name) 取不到，改用文字兜底")
        }
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
        // 图标按用户要求保持原样：在线 = 圆圈+闪电，其余用状态盾牌/圆圈。
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
        setStatusImage(name, on: button)
    }

    // MARK: 图标位置自校正

    /// 量图标按钮在屏幕上的真实矩形。刚启动、菜单栏还没布局时可能拿不到，返回 nil。
    private func statusButtonFrame() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.width > 1, frame.height > 1 else { return nil }
        return frame
    }

    private func schedulePlacementCheck(after delay: Duration) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            self.checkStatusItemPlacement()
        }
    }

    /// 图标是不是真的在屏幕右半边（用户说的"右上角"）。
    /// 不猜坐标、不信任 AppKit 的默认摆放——只量按钮此刻在屏幕上的真实位置。
    private func checkStatusItemPlacement() {
        guard placementProbeCount < 8 else {
            FileLogger.shared.log("图标：多次都量不到真实位置，本轮的自动校正放弃")
            return
        }
        placementProbeCount += 1

        guard let frame = statusButtonFrame(),
              let screen = statusItem?.button?.window?.screen ?? NSScreen.main else {
            FileLogger.shared.log("图标：还没量到真实位置，800ms 后再看（第 \(placementProbeCount) 次）")
            schedulePlacementCheck(after: .milliseconds(800))
            return
        }

        let mid = screen.frame.midX
        FileLogger.shared.log("图标：位置 x=\(Int(frame.minX))…\(Int(frame.maxX))，"
                              + "屏宽 \(Int(screen.frame.width))，中线 \(Int(mid))")
        var misplaced = frame.midX < mid
        if DevOverrides.healPlacementOnLaunch && !devHealUsed {
            devHealUsed = true
            misplaced = true
            FileLogger.shared.log("图标：自检开关要求，按「被摆到左边」走一次重建")
        }
        guard misplaced else { return }

        if placementAttempt == 0 {
            baselineIconX = frame.midX
        } else if let baseline = baselineIconX, frame.midX < baseline - 20 {
            // 写了位置偏好反而更靠左 → 这台系统不是"离右边多少点"的语义，
            // 再写小值只会更糟。撤回偏好，回到系统默认摆放，本轮到此为止。
            FileLogger.shared.log("图标：位置偏好反而把它推得更左（\(Int(baseline)) → \(Int(frame.midX))），"
                                  + "撤回偏好、回默认摆放")
            revertStatusItemPlacement()
            return
        }
        healStatusItemPlacement(reason: "图标落在屏幕左半边")
    }

    /// 撤回位置偏好：换一个全新的 autosaveName、不写任何偏好，让系统按默认规则摆放。
    private func revertStatusItemPlacement() {
        placementAttempt = placementValues.count      // 本轮不再重排
        let generation = UserDefaults.standard.integer(forKey: Self.autosaveGenerationKey) + 1
        UserDefaults.standard.set(generation, forKey: Self.autosaveGenerationKey)
        let name = "JLUGate.d\(generation)"
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
        }
        createStatusItem(autosaveName: name)
        FileLogger.shared.log("图标：已回到默认摆放（autosave=\(name)）")
    }

    /// 把图标挪回右侧：换一个新的 autosaveName，并在建图标之前写死位置偏好。
    ///
    /// `NSStatusItem Preferred Position` 是 AppKit 自己持久化图标顺序用的键（值越小越靠右，
    /// 菜单栏管理类 App 都用它排序）。实测：先写值、再建图标，系统就会把图标排到
    /// "离屏幕右边约 N 点"的位置；300 正好落在其他菜单栏 App 那一排。
    /// 必须换新名字——同一个 autosaveName 的值会被 AppKit 缓存/清掉，重建也不生效。
    private func healStatusItemPlacement(reason: String) {
        guard placementAttempt < placementValues.count else {
            FileLogger.shared.log("图标：两次重排后仍不在右半边，保持现状（日志里已记录实际坐标）")
            return
        }
        let value = placementValues[placementAttempt]
        placementAttempt += 1
        var generation = UserDefaults.standard.integer(forKey: Self.autosaveGenerationKey) + 1
        var name = "JLUGate.g\(generation)"
        // 万一算出来的名字正好是现在用的那个（老版本留下的），再往后跳一代
        let currentName = UserDefaults.standard.string(forKey: Self.autosaveNameKey)
        while name == currentName {
            generation += 1
            name = "JLUGate.g\(generation)"
        }
        UserDefaults.standard.set(generation, forKey: Self.autosaveGenerationKey)
        UserDefaults.standard.set(value, forKey: Self.preferredPositionPrefix + name)
        UserDefaults.standard.synchronize()

        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
        }
        createStatusItem(autosaveName: name)
        FileLogger.shared.log("图标：\(reason)，已重建到右侧（autosave=\(name)，"
                              + "preferredPosition=\(Int(value))）")

        // 图标挪了位置：面板如果正开着，等落位后重新贴一次
        if popover?.isShown == true {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                self.showPanel()
            }
        }
        schedulePlacementCheck(after: .milliseconds(1200))
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
    /// 真机上的坑（macOS 14）：启动阶段就 show 的话，状态栏图标可能还没被系统摆到
    /// 最终位置，NSPopover 会锚在那一刻的坐标上，于是整块面板落在别处（上次是屏幕
    /// 左上角）。这里不再拿坐标硬判（不同系统、不同菜单栏布局下并不可靠），改成：
    /// 先 show，1.2 秒后再比对一次锚点，图标挪过位就收起、按新位置重新锚定。
    func showPanel(retry: Int = 0) {
        guard let model, let button = statusItem?.button else { return }

        // 按钮还没进窗口：晚一点再试，别静默失败
        guard button.window != nil else {
            guard retry < 10 else {
                FileLogger.shared.log("面板：状态栏按钮一直不在窗口里，放弃显示")
                return
            }
            retryPanelShow(retry)
            return
        }

        // 先激活再 show：非活跃的 accessory App 某些系统上会把 popover 放歪
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
        let anchor = statusButtonFrame()
        FileLogger.shared.log("面板：已显示（锚点 x=\(Int(anchor?.minX ?? -1)) y=\(Int(anchor?.minY ?? -1))）")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.verifyPanelPlacement()
        }
    }

    // MARK: 锚点自校正

    /// 校验"面板真的贴在图标下面"。
    ///
    /// 只认两条硬指标：面板和图标在横向上有重叠；面板上沿贴着菜单栏（不是掉到屏幕中间）。
    /// 不比对中心点——图标靠右时 popover 会被屏幕边缘挤过来，中心点本来就不重合。
    /// 不对就收起重开，最多 2 次，每次都把实测数字写进日志。
    private func verifyPanelPlacement(attempt: Int = 0) {
        guard popover?.isShown == true,
              let anchor = statusButtonFrame(),
              let win = popover?.contentViewController?.view.window else { return }
        let overlaps = win.frame.minX < anchor.maxX && win.frame.maxX > anchor.minX
        let gapY = abs(win.frame.maxY - anchor.minY)
        if overlaps && gapY <= 80 {
            FileLogger.shared.log("面板：位置正常（面板 x=\(Int(win.frame.minX))…\(Int(win.frame.maxX))，"
                                  + "图标 x=\(Int(anchor.minX))…\(Int(anchor.maxX))）")
            return
        }
        guard attempt < 2 else {
            FileLogger.shared.log("面板：重开 2 次仍没贴住图标（overlaps=\(overlaps) gapY=\(Int(gapY))）")
            return
        }
        popover?.performClose(nil)
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        FileLogger.shared.log("面板：没贴住图标（overlaps=\(overlaps) gapY=\(Int(gapY))），已收起重开（\(attempt + 1)/2）")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.verifyPanelPlacement(attempt: attempt + 1)
        }
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
