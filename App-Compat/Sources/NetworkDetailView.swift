import SwiftUI
import JLUGateCore
import JLUGateNet

/// 「网络详情」窗口：把终端里才看得到的东西摊开给用户，并逐项解释。
struct NetworkDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    proxyModeSection
                    vpnSection
                    interfaceSection
                    routeSection
                    authLivenessSection
                    pingSection
                    speedSection
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { Task { @MainActor in model.refreshNetworkDetail() } }
    }

    private var snapshot: NetworkSnapshot? { model.networkSnapshot }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: (snapshot?.vpnIsActive ?? false) ? "lock.shield.fill" : "network")
                .font(.title2)
                .foregroundStyle((snapshot?.vpnIsActive ?? false) ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.t("D01")).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(Copy.t("D02")) { model.refreshNetworkDetail() }
                .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private var subtitle: String {
        guard let snapshot else { return Copy.t("D03") }
        let vpn = snapshot.vpnIsActive ? Copy.t("D04") : Copy.t("D05")
        let dns = snapshot.dnsLooksHijacked ? Copy.t("D06") : ""
        return "\(vpn)\(dns)"
    }

    // MARK: 代理模式

    private var proxyModeSection: some View {
        card(Copy.t("D07")) {
            if let analysis = model.proxyAnalysis {
                HStack(spacing: 8) {
                    Image(systemName: icon(for: analysis.mode))
                        .foregroundStyle(color(for: analysis.mode))
                    Text(analysis.mode.title).font(.subheadline.bold())
                    Spacer()
                    if let matches = analysis.matchesDeclared {
                        Label(matches ? Copy.t("D08") : Copy.t("D09"),
                              systemImage: matches ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(matches ? .green : .orange)
                    }
                }
                Text(analysis.summary).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(analysis.advice, systemImage: "lightbulb")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.t("D10")).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text(Copy.t("D11")).font(.caption2).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { model.config.declaredProxyMode },
                    set: { model.setDeclaredProxyMode($0) })) {
                    ForEach(DeclaredProxyMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    private func icon(for mode: ProxyMode) -> String {
        switch mode {
        case .direct: "arrow.right.circle"
        case .ruleSplit: "arrow.triangle.branch"
        case .global: "arrow.triangle.2.circlepath.circle"
        case .tunnelIdle: "pause.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private func color(for mode: ProxyMode) -> Color {
        switch mode {
        case .ruleSplit, .direct: .green
        case .global: .orange
        case .tunnelIdle: .yellow
        case .unknown: .secondary
        }
    }

    // MARK: VPN

    private var vpnSection: some View {
        card("VPN / TUN") {
            if let snapshot, !snapshot.tunnels.isEmpty {
                ForEach(snapshot.tunnels) { tunnel in
                    LabeledContent(tunnel.name) {
                        Text("\(tunnel.ipv4 ?? "无地址")　\(tunnel.isUp ? "已启用" : "未启用")")
                            .font(.caption.monospaced())
                    }
                }
            } else {
                Text(Copy.t("D12"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let route = snapshot?.defaultRoute {
                LabeledContent(Copy.t("D13")) {
                    Text("\(route.interface ?? "?")\(route.isTunnel ? "（虚拟网卡）" : "")")
                        .font(.caption.monospaced())
                }
            }
            if let route = snapshot?.campusRoute {
                LabeledContent(Copy.t("D14")) {
                    Text("10.100.61.3 → \(route.interface ?? "?")\(route.isTunnel ? " ⚠️ 会被代理吞掉" : "")")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    // MARK: 网口

    private var interfaceSection: some View {
        card(Copy.t("D15")) {
            ForEach(snapshot?.interfaces ?? []) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.name).font(.caption.bold().monospaced())
                        if row.isWireless { tag(Copy.t("D16"), .blue) }
                        if row.isUSB { tag("USB", .purple) }
                        if row.isDefaultRoute { tag("默认出口", .green) }
                        if row.carriesCampusRoute { tag(Copy.t("D17"), .orange) }
                        Spacer()
                        Text(row.isUp ? Copy.t("D18") : Copy.t("D19"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("IPv4 \(row.ipv4 ?? "—") / \(row.mask ?? "—")　MAC \(row.mac ?? "—")")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    if let hardware = row.hardwareMAC, hardware.lowercased() != (row.mac ?? "").lowercased() {
                        Text(Copy.f("D20", hardware))
                            .font(.caption2.monospaced()).foregroundStyle(.orange)
                    }
                    Text(explanationTitle(for: row)).font(.caption2).foregroundStyle(.secondary)
                    Text(explanationNote(for: row)).font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let linkLocal = row.linkLocal {
                        Text(Copy.f("D21", linkLocal)).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 3)
            }
            if (snapshot?.interfaces ?? []).isEmpty {
                Text(Copy.t("D22")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var routeSection: some View {
        card(Copy.t("D23")) {
            if let route = snapshot?.defaultRoute {
                LabeledContent(Copy.t("D24")) {
                    Text(Copy.f("D25", route.interface ?? "?", route.gateway ?? "—"))
                        .font(.caption.monospaced())
                }
            }
            let dns = snapshot?.dnsServers ?? []
            LabeledContent(Copy.t("D26")) {
                Text(dns.isEmpty ? Copy.t("D27") : dns.joined(separator: ", "))
                    .font(.caption.monospaced())
            }
            if snapshot?.dnsLooksHijacked == true {
                Label(Copy.t("D28"),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    // MARK: 认证通道（不是模式，是实际延迟）

    private var authLivenessSection: some View {
        card(Copy.t("D29")) {
            Text(Copy.t("D30"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let sample = model.authLiveness {
                Text(sample.direct.description).font(.caption.monospaced())
                Text(sample.viaDefault.description).font(.caption.monospaced())
                Label(sample.verdict, systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 测量入口统一挪到「体检」页，这里只显示结果
        }
    }

    // MARK: Ping

    private var pingSection: some View {
        card(Copy.t("D33")) {
            if model.pingResults.isEmpty {
                Text(Copy.t("D34"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.pingResults, id: \.host) { summary in
                    Text(summary.description).font(.caption.monospaced())
                }
            }
            // 测量入口统一挪到「体检」页，这里只显示结果
        }
    }

    // MARK: 测速

    private var speedSection: some View {
        card(Copy.t("D36")) {
            if model.speedResults.isEmpty {
                Text(Copy.t("D37"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.speedResults, id: \.self) { result in
                    Text(result.description).font(.caption.monospaced())
                }
                if !model.speedResults.contains(where: { $0.boundInterface != nil }) {
                    Label(Copy.t("D38"),
                          systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            // 测速按钮挪到「体检」页，这里只显示最近一次结果
        }
    }

    // MARK: 字段含义（内联到各卡片，不再单独列一块）

    private func footnote(_ id: String) -> some View {
        Group {
            if let text = FieldGuide.explanation(for: id) {
                Text(text)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack {
            Button(Copy.t("D41")) { model.copyNetworkDetail() }
                .buttonStyle(.bordered)
            Spacer()
            Button(Copy.t("D42")) { model.closeNetworkDetail() }
                .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: 小工具

    private func card<Content: View>(_ title: String, notes: [String] = [],
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
            ForEach(notes, id: \.self) { id in
                if let text = FieldGuide.explanation(for: id) {
                    Text(text).font(.system(size: 9)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jluGlassCard()
    }

    private func explanation(for row: NetworkSnapshot.InterfaceRow) -> InterfaceExplanation {
        InterfaceNarrator.explain(name: row.name, hardwareName: row.hardwareName,
                                  isWireless: row.isWireless, isUSB: row.isUSB,
                                  ipv4: row.ipv4,
                                  proxyApps: model.detectedProxyAppNames)
    }

    private func explanationTitle(for row: NetworkSnapshot.InterfaceRow) -> String {
        let info = explanation(for: row)
        return "\(info.title) · \(info.owner)"
    }

    private func explanationNote(for row: NetworkSnapshot.InterfaceRow) -> String {
        explanation(for: row).note
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
