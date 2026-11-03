import SwiftUI
import JLUGateCore

/// 菜单栏下拉内容（`.menuBarExtraStyle(.window)`），全部用系统 Liquid Glass，不自绘毛玻璃。
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Namespace private var glassNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassEffectContainer(spacing: 12) {
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
                .glassEffect(.regular.tint(model.statusColor.opacity(0.55)).interactive(),
                             in: .rect(cornerRadius: 16))
                .glassEffectID("status", in: glassNamespace)
            }

            actionButtons

            footer
        }
        .padding(14)
        .frame(width: 348)
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
                if model.state.isOnline || model.state.isBusy {
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
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            if model.canOpenPortalLogin {
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
                    Label("重新填写网络参数", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

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
