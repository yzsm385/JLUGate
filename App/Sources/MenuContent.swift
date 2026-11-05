import SwiftUI
import Combine
import JLUGateCore

/// 菜单栏下拉内容（`.menuBarExtraStyle(.window)`），全部用系统 Liquid Glass，不自绘毛玻璃。
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    /// 每秒刷新一次，让"已在线"的时长真的在走
    @State private var now = Date()

    var body: some View {
        Group {
            switch model.panel {
            case .main:
                mainPanel
            case .wizard:
                embedded { WizardView() }
            case .settings:
                embedded { SettingsView() }
            case .detail:
                embedded { NetworkDetailView() }
            case .status:
                embedded { ConnectionStatusView() }
            case .inspect:
                embedded { InspectPanel() }
            case .sites:
                embedded { SitesPanel() }
            case .developer:
                embedded { DeveloperPanel() }
            case .portal:
                embedded { PortalViewerView(url: model.portalViewerURL) }
            case .portalLogin:
                embedded {
                    if let url = model.pendingPortalLoginURL {
                        PortalLoginPanel(url: url)
                    } else {
                        Text(Copy.t("M01")).font(.caption)
                    }
                }
            }
        }
    }

    /// 子页面统一套一层"返回"头：所有界面都在菜单栏面板里，不再开独立窗口。
    private func embedded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    model.show(.main)
                } label: {
                    Label(Copy.t("M02"), systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            // 关键：面板宽度固定、内容可滚动。
            // 之前子页面带着 540~640 的写死宽度塞进 360 的面板里，直接把布局撑爆。
            // 高度**跟着内容走**（最多 520）：短页面不再留一大块空白。
            FittingScrollView(maxHeight: 520) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 380)
        .padding(12)
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 原生 Liquid Glass：状态卡与操作按钮放在同一个容器里，
            // 邻近元素会被系统合并成一块连续的玻璃（不是叠两层自绘材质）。
            VStack(alignment: .leading, spacing: 10) {
                statusCard
                actionButtons
            }

            updateBar
            offCampusAssist
            footer
        }
        .padding(14)
        .frame(width: 348)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            // 只有"在线 + 面板可见"时才需要每秒刷新，其余时候不动，省 CPU
            if model.state.isOnline, model.isPanelVisible { now = tick }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.35)
            detailGrid
            if case .failed(let error) = model.state {
                VStack(alignment: .leading, spacing: 3) {
                    Text(error.userMessage)
                        .font(.system(size: 10)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if error.requiresUserAction {
                        Text(Copy.t("M03"))
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.recentLog.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.recentLog.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 9)).foregroundStyle(.tertiary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let action = model.statusStory.action {
                Label(action, systemImage: "hand.point.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .jluGlassStatus(cornerRadius: 18, tint: model.statusColor)
    }

    // MARK: 状态卡

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.statusSymbol)
                .font(.title2)
                .symbolEffect(.pulse, isActive: model.state.isBusy)
                .foregroundStyle(model.statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusStory.title + AppIdentity.displaySuffix).font(.headline)
                Text(model.statusStory.oneLiner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow(Copy.t("M04"), model.linkTitle, hint: linkHint)
            if let ip = model.clientIP {
                detailRow(Copy.t("M05"), ip, hint: Copy.t("M06"), mono: true)
            }
            if model.state.isOnline {
                detailRow(Copy.t("M07"), timeText, hint: Copy.t("M08"), mono: true)
            }
            detailRow(Copy.t("M09"), model.routeSummary,
                      hint: Copy.t("M10"), small: true)
        }
    }

    /// 一行明细：左边标签，右边值，值下面一句人话注解（说明贴着它自己那一行）
    private func detailRow(_ label: String, _ value: String,
                           hint: String, mono: Bool = false, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(mono ? .caption.monospacedDigit() : (small ? .caption2 : .caption))
                    .lineLimit(2)
                Text(hint).font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var linkHint: String {
        switch model.config.link {
        case "wired": Copy.t("M11")
        case "jluPC": Copy.t("M12")
        case "jluWiFi": Copy.t("M13")
        default: Copy.t("M14")
        }
    }

    /// 在线时长：以 lastOnlineAt 为起点**实时计算**。
    /// 以前只读引擎上报的 secondsOnline，心跳一停就冻住不动。
    private var timeText: String {
        let total: Int
        if let start = model.lastOnlineAt {
            total = max(0, Int(now.timeIntervalSince(start)))
        } else {
            total = Int(model.secondsOnline)
        }
        let absolute = model.lastOnlineAt.map {
            DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
        }
        let duration = String(format: "%d:%02d", total / 60, total % 60)
        return absolute.map { Copy.f("M15", $0, duration) } ?? duration
    }

    // MARK: 动作

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if model.observingExistingSession, !model.hasStoredCredentials {
                    // 用户本来就在线（浏览器里登录过），我们只是如实显示；
                    // 给他一个"顺手把账号记下来"的入口，断线后能自动重连。
                    Button {
                        model.presentWizard()
                    } label: {
                        Label(Copy.t("M16"), systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if model.state.isOnline || model.state.isBusy
                            || model.observingExistingSession {
                    Button {
                        model.disconnect()
                    } label: {
                        Label(Copy.t("M17"), systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.connect()
                    } label: {
                        Label(Copy.t("M18"), systemImage: "bolt.horizontal.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.config.account.isEmpty)
                }

                if case .failed = model.state {
                    Button {
                        model.retry()
                    } label: {
                        Label(Copy.t("M19"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if case .failed(let error) = model.state, error.requiresUserAction {
                Text(error.userMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = accountConflictHint(for: error) {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if error.isCredentialRejection {
                    Button {
                        model.presentWizard()
                    } label: {
                        Label(Copy.t("M20"), systemImage: "key")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                }
                if case .macRejected = error { macFixButtons }
                if case .macMismatch = error { macFixButtons }
            }

            if case .manual(let command, _) = model.routeGuarantee, !model.state.isOnline {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.t("M21"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(command)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                    HStack {
                        Button(Copy.t("M22")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        Button(Copy.t("M23")) { model.refreshDiagnostics() }
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
                .padding(10)
                .jluGlassCard(cornerRadius: 12)
            }

            if model.portalLimitNotice != nil, !model.state.isOnline {
                VStack(alignment: .leading, spacing: 6) {
                    Label(Copy.f("M24", JLUWiFiLimits.maxDevices), systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(JLUWiFiLimits.reclaimNotice)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.reclaimPortal()
                    } label: {
                        Label(Copy.t("M25"), systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .jluGlassCard(cornerRadius: 12)
            } else if model.canOpenPortalLogin {
                Button {
                    model.openPortalLogin()
                } label: {
                    Label(Copy.t("M26"), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !model.isConfigured {
                Button {
                    model.presentWizard()
                } label: {
                    Label(Copy.t("M27"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// MAC 类错误的两个动作：改用检测到的出厂 MAC / 去自助平台改登记
    private var macFixButtons: some View {
        HStack(spacing: 10) {
            if let detected = model.interfaceCandidates.first(where: { $0.name == model.config.interfaceLock })?
                .macForAuthentication
                ?? model.interfaceCandidates.first(where: { $0.ipv4 != nil })?.macForAuthentication {
                Button {
                    model.adoptDetectedMAC()
                    model.retry()
                } label: {
                    Label(Copy.f("M28", detected), systemImage: "wand.and.stars")
                        .font(.caption2)
                }
                .buttonStyle(.link)
            }
            openSelfServiceButton
        }
    }

    private var openSelfServiceButton: some View {
        Button {
            NSWorkspace.shared.open(JLUAccessPolicy.selfServiceURL)
        } label: {
            Label(Copy.t("M29"), systemImage: "safari")
                .font(.caption2)
        }
        .buttonStyle(.link)
    }

    /// 顶号时补一句"怎么办"（服务器原文已经在上面一行里了，不替代它）。
    private func accountConflictHint(for error: DrcomError) -> String? {
        switch error {
        case .accountInUse:
            return Copy.t("M30")
        case .macInUse:
            return Copy.t("M31")
        case .macRejected:
            return JLUAccessPolicy.rejectedByMacHint
        case .macMismatch(let expected, let actual):
            if let actualMAC = actual.flatMap(MACAddress.init), actualMAC.isLocallyAdministrated {
                return JLUAccessPolicy.privateMACHint(current: actual ?? "-", hardware: nil,
                                                      registered: expected)
            }
            return JLUAccessPolicy.macMismatchHint(expected: expected, actual: actual)
        default:
            return nil
        }
    }

    @ViewBuilder
    private var offCampusAssist: some View {
        if model.isOffCampus {
            WebVPNAssistCard()
        }
    }

    private var footer: some View {
        // 380 宽放不下一行 7 个按钮：改成两行、等宽网格，图标在上文字在下
        HStack(spacing: 2) {
            footerButton(Copy.t("M32"), "gearshape") { model.presentSettings() }
            footerButton(Copy.t("M33"), "link") { model.show(.sites) }
            footerButton(Copy.t("M34"), "network") { model.presentNetworkDetail() }
            footerButton(Copy.t("M35"), "stethoscope.circle") { model.show(.developer) }
            footerButton(Copy.t("M36"), "stethoscope") { model.show(.inspect) }
            footerButton(Copy.t("M37"), "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 2)
    }

    private func footerButton(_ title: String, _ symbol: String,
                              action: @escaping () -> Void) -> some View {
        // 底栏不放 emoji：已经有 SF Symbol 图标，emoji 会把文字挤到下一行
        let label = Copy.withoutEmoji(title)
        return Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(label).font(.system(size: 9.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: 更新

    private var updateSummary: (icon: String, text: String, tint: Color) {
        if model.updateInstalling, let message = model.updateInstallMessage {
            return ("arrow.down.circle", message, .orange)
        }
        switch model.updateStatus {
        case .idle:
            return ("arrow.triangle.2.circlepath", Copy.t("M38"), .secondary)
        case .checking:
            return ("arrow.triangle.2.circlepath", Copy.t("M39"), .secondary)
        case .upToDate:
            return ("checkmark.circle", Copy.f("M40", BuildInfo.version), .green)
        case .available(let tag, _, _, _):
            return ("arrow.down.circle.fill", Copy.f("M41", tag), .orange)
        case .failed(let message):
            return ("exclamationmark.triangle", message, .orange)
        }
    }

    private var updateButtonTitle: String {
        switch model.updateStatus {
        case .available: Copy.t("M42")
        case .checking: Copy.t("M43")
        case .failed: Copy.t("M19")
        case .upToDate: Copy.t("M44")
        case .idle: Copy.t("M42")
        }
    }

    /// 面板上的一行更新入口：查最新 → 下载 → 退出替换 → 重新打开（安装包会自己清掉）
    private var updateBar: some View {
        HStack(spacing: 6) {
            Image(systemName: updateSummary.icon).font(.system(size: 10))
            Text(updateSummary.text)
                .font(.system(size: 10))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(updateButtonTitle) { model.updateNow() }
                .controlSize(.mini)
                .buttonStyle(.bordered)
                .disabled(model.updateInstalling || model.updateStatus == .checking)
        }
        .foregroundStyle(updateSummary.tint)
        .padding(.horizontal, 2)
    }
}

/// 高度跟着内容走的滚动区：内容短就短，超过上限才开始滚动。
/// 菜单栏面板的高度是内容撑出来的，写死 520 会在短页面下面留一大块空白。
private struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    private let content: Content
    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: contentHeight > maxHeight) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PanelContentHeightKey.self,
                                               value: proxy.size.height)
                    }
                )
        }
        .frame(height: contentHeight == 0 ? maxHeight : min(contentHeight, maxHeight))
        .onPreferenceChange(PanelContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
