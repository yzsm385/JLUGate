import SwiftUI
import JLUGateCore

/// 菜单栏下拉内容（`.menuBarExtraStyle(.window)`），全部用系统 Liquid Glass，不自绘毛玻璃。
struct MenuContent: View {
    @Environment(AppModel.self) private var model

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
            case .portal:
                embedded { PortalViewerView(url: model.portalViewerURL) }
            case .portalLogin:
                embedded {
                    if let url = model.pendingPortalLoginURL {
                        PortalLoginPanel(url: url)
                    } else {
                        Text("没有待完成的网页认证").font(.caption)
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
                    Label("返回", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            // 关键：面板宽度固定、内容可滚动。
            // 之前子页面带着 540~640 的写死宽度塞进 360 的面板里，直接把布局撑爆。
            ScrollView(.vertical, showsIndicators: true) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 520)
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

            offCampusAssist
            campusAdRow
            footer
        }
        .padding(14)
        .frame(width: 348)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.35)
            detailGrid
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
                Text(model.statusStory.title).font(.headline)
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
            detailRow("链路", model.linkTitle, hint: linkHint)
            if let ip = model.clientIP {
                detailRow("本机 IP", ip, hint: "学校分给这台机器的门牌号", mono: true)
            }
            if model.state.isOnline {
                detailRow("已在线", timeText, hint: "这期间认证一直在续，不用你管", mono: true)
            }
            detailRow("出口", model.routeSummary,
                      hint: "认证包从哪张网卡出去；走代理不一定坏，但慢/丢包会被判掉线", small: true)
        }
    }

    /// 一行明细：左边标签，右边值，值下面一句人话注解（说明贴着它自己那一行）
    private func detailRow(_ label: String, _ value: String,
                           hint: String, mono: Bool = false, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
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
        case "wired": "插网线的那种，最稳"
        case "jluPC": "学校无线信号，要用 Wi-Fi 网卡的身份认证"
        case "jluWiFi": "网页登录那种，走浏览器"
        default: "自动：先探一下再决定用哪条路"
        }
    }

    private var timeText: String {
        let total = Int(model.secondsOnline)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: 动作

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if model.observingExistingSession {
                    // 用户本来就在线（浏览器里登录过），我们只是如实显示；
                    // 给他一个"顺手把账号记下来"的入口，断线后能自动重连。
                    Button {
                        model.presentWizard()
                    } label: {
                        Label("填写账号密码（断线后自动重连）", systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if model.state.isOnline || model.state.isBusy {
                    Button {
                        model.disconnect()
                    } label: {
                        Label("下线", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.connect()
                    } label: {
                        Label("登录", systemImage: "bolt.horizontal.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.config.account.isEmpty)
                }

                if case .failed = model.state {
                    Button {
                        model.retry()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
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
                        Label("重新输入密码", systemImage: "key")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                }
                if case .macRejected = error { macFixButtons }
                if case .macMismatch = error { macFixButtons }
            }

            if case .manual(let command, _) = model.routeGuarantee, !model.state.isOnline {
                VStack(alignment: .leading, spacing: 4) {
                    Text("代理接管了校园网段，需要先加一条直连路由：")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(command)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                    HStack {
                        Button("复制命令") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        Button("我已执行，重新检测") { model.refreshDiagnostics() }
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
                .padding(10)
                .jluGlassCard(cornerRadius: 12)
            }

            if model.portalLimitNotice != nil, !model.state.isOnline {
                VStack(alignment: .leading, spacing: 6) {
                    Label("JLU.WIFI 同时最多 \(JLUWiFiLimits.maxDevices) 台设备", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(JLUWiFiLimits.reclaimNotice)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.reclaimPortal()
                    } label: {
                        Label("重新抢回在线", systemImage: "arrow.uturn.backward.circle")
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
                    Label("打开网页登录页", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !model.isConfigured {
                Button {
                    model.presentWizard()
                } label: {
                    Label("重新设置…", systemImage: "wand.and.stars")
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
                    Label("改用出厂 MAC \(detected)", systemImage: "wand.and.stars")
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
            Label("打开自助平台（改登记 MAC）", systemImage: "safari")
                .font(.caption2)
        }
        .buttonStyle(.link)
    }

    /// 顶号时补一句"怎么办"（服务器原文已经在上面一行里了，不替代它）。
    private func accountConflictHint(for error: DrcomError) -> String? {
        switch error {
        case .accountInUse:
            return "同一账号同一时刻只能一台设备在线。想让本机上线：到那台设备上退出（或等约 30 秒自动释放）再点重试。"
        case .macInUse:
            return "这个 MAC 已被别的设备占用。若你换了网卡/共用廉价网卡，请到学校平台核对登记。"
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

    /// 校园广告/门户：主面板直接给入口（以前只藏在体检页，等于没有）
    private var campusAdRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    model.openCampusAd()
                } label: {
                    Label("看校园广告 / 门户", systemImage: "megaphone")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            if let status = model.campusAdStatus {
                Text(status).font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                footerButton("设置", "gearshape") { model.presentSettings() }
                footerButton("站点", "link") { model.show(.sites) }
                footerButton("状态", "info.circle") { model.presentConnectionStatus() }
                footerButton("详情", "network") { model.presentNetworkDetail() }
                footerButton("体检", "stethoscope") { model.show(.inspect) }
            }
            HStack(spacing: 2) {
                footerButton("导出", "square.and.arrow.up") { model.exportDiagnostics() }
                footerButton("参数卡", "qrcode") { model.exportConfigCard() }
                footerButton("诊断", "doc.on.clipboard") { model.copyDiagnostics() }
                footerButton("退出", "power") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(.horizontal, 2)
    }

    private func footerButton(_ title: String, _ symbol: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
