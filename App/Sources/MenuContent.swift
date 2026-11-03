import SwiftUI
import JLUGateCore

/// 菜单栏下拉内容（`.menuBarExtraStyle(.window)`），全部用系统 Liquid Glass，不自绘毛玻璃。
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Namespace private var glassNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 原生 Liquid Glass：状态卡与操作按钮放在同一个容器里，
            // 邻近元素会被系统合并成一块连续的玻璃（不是叠两层自绘材质）。
            GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    statusCard
                        .glassEffectID("status", in: glassNamespace)

                    actionButtons
                        .glassEffectID("actions", in: glassNamespace)
                }
            }

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
            if !model.recentLog.isEmpty {
                Text(model.recentLog.prefix(3).joined(separator: "\n"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .glassEffect(.regular.tint(model.statusColor.opacity(0.5)).interactive(),
                     in: .rect(cornerRadius: 18))
    }

    // MARK: 状态卡

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.statusSymbol)
                .font(.title2)
                .symbolEffect(.pulse, isActive: model.state.isBusy)
                .foregroundStyle(model.statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusTitle).font(.headline)
                Text(model.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("链路").font(.caption).foregroundStyle(.secondary)
                Text(model.linkTitle).font(.caption)
            }
            if let ip = model.clientIP {
                GridRow {
                    Text("本机 IP").font(.caption).foregroundStyle(.secondary)
                    Text(ip).font(.caption).monospacedDigit()
                }
            }
            if model.state.isOnline {
                GridRow {
                    Text("本次在线").font(.caption).foregroundStyle(.secondary)
                    Text(timeText).font(.caption).monospacedDigit()
                }
            }
            GridRow {
                Text("接口").font(.caption).foregroundStyle(.secondary)
                Text(model.routeSummary).font(.caption2).foregroundStyle(.secondary)
            }
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
                    .buttonStyle(.glass)
                } else if model.state.isOnline || model.state.isBusy {
                    Button {
                        model.disconnect()
                    } label: {
                        Label("下线", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        model.connect()
                    } label: {
                        Label("登录", systemImage: "bolt.horizontal.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(model.config.account.isEmpty)
                }

                if case .failed = model.state {
                    Button {
                        model.retry()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
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
                .glassEffect(.clear, in: .rect(cornerRadius: 12))
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
                    .buttonStyle(.glass)
                }
                .padding(10)
                .glassEffect(.clear, in: .rect(cornerRadius: 12))
            } else if model.canOpenPortalLogin {
                Button {
                    model.openPortalLogin()
                } label: {
                    Label("打开网页登录页", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }

            if !model.isConfigured {
                Button {
                    model.presentWizard()
                } label: {
                    Label("重新设置…", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
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

    private var footer: some View {
        HStack {
            Button {
                model.presentSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

            if model.portalViewerURL != nil {
                Button {
                    model.presentPortalViewer()
                } label: {
                    Label("校园网门户", systemImage: "globe.asia.australia")
                }
                .buttonStyle(.plain)
            }

            Button {
                model.presentNetworkDetail()
            } label: {
                Label("网络详情", systemImage: "network")
            }
            .buttonStyle(.plain)

            Button {
                model.copyDiagnostics()
            } label: {
                Label("复制诊断", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)

            Button {
                model.exportDiagnostics()
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            Button {
                model.exportConfigCard()
            } label: {
                Label("参数卡", systemImage: "qrcode")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
