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
                Text("网络详情").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("刷新") { model.refreshNetworkDetail() }
                .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private var subtitle: String {
        guard let snapshot else { return "正在读取…" }
        let vpn = snapshot.vpnIsActive ? "VPN/TUN 已接管" : "VPN/TUN 未接管"
        let dns = snapshot.dnsLooksHijacked ? " · DNS 被代理劫持" : ""
        return "\(vpn)\(dns)"
    }

    // MARK: 代理模式

    private var proxyModeSection: some View {
        card("代理模式（对照小火箭）") {
            if let analysis = model.proxyAnalysis {
                HStack(spacing: 8) {
                    Image(systemName: icon(for: analysis.mode))
                        .foregroundStyle(color(for: analysis.mode))
                    Text(analysis.mode.title).font(.subheadline.bold())
                    Spacer()
                    if let matches = analysis.matchesDeclared {
                        Label(matches ? "与你的选择一致" : "与你的选择不一致",
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
                Text("正在判断…").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text("你在小火箭里选的是：").font(.caption2).foregroundStyle(.secondary)
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
                Text("没有 utun 接口：当前没有代理/VPN 在抢路由。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let route = snapshot?.defaultRoute {
                LabeledContent("默认出口") {
                    Text("\(route.interface ?? "?")\(route.isTunnel ? "（虚拟网卡）" : "")")
                        .font(.caption.monospaced())
                }
            }
            if let route = snapshot?.campusRoute {
                LabeledContent("认证流量出口") {
                    Text("10.100.61.3 → \(route.interface ?? "?")\(route.isTunnel ? " ⚠️ 会被代理吞掉" : "")")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    // MARK: 网口

    private var interfaceSection: some View {
        card("网口") {
            ForEach(snapshot?.interfaces ?? []) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.name).font(.caption.bold().monospaced())
                        if row.isWireless { tag("无线", .blue) }
                        if row.isUSB { tag("USB", .purple) }
                        if row.isDefaultRoute { tag("默认出口", .green) }
                        if row.carriesCampusRoute { tag("认证流量", .orange) }
                        Spacer()
                        Text(row.isUp ? "已启用" : "未启用")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("IPv4 \(row.ipv4 ?? "—") / \(row.mask ?? "—")　MAC \(row.mac ?? "—")")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    if let hardware = row.hardwareMAC, hardware.lowercased() != (row.mac ?? "").lowercased() {
                        Text("出厂 MAC \(hardware)　←　认证用的是这个（系统当前是私有/随机地址）")
                            .font(.caption2.monospaced()).foregroundStyle(.orange)
                    }
                    Text(explanationTitle(for: row)).font(.caption2).foregroundStyle(.secondary)
                    Text(explanationNote(for: row)).font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let linkLocal = row.linkLocal {
                        Text("链路本地 \(linkLocal)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 3)
            }
            if (snapshot?.interfaces ?? []).isEmpty {
                Text("没有物理网口").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var routeSection: some View {
        card("路由与 DNS") {
            if let route = snapshot?.defaultRoute {
                LabeledContent("默认路由") {
                    Text("\(route.interface ?? "?")（网关 \(route.gateway ?? "—")）")
                        .font(.caption.monospaced())
                }
            }
            let dns = snapshot?.dnsServers ?? []
            LabeledContent("系统 DNS") {
                Text(dns.isEmpty ? "（读不到）" : dns.joined(separator: ", "))
                    .font(.caption.monospaced())
            }
            if snapshot?.dnsLooksHijacked == true {
                Label("系统 DNS 是 198.18.x.x（代理的 fake-ip）。本程序的探针不用它，自己发 UDP 查询。",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    // MARK: 认证通道（不是模式，是实际延迟）

    private var authLivenessSection: some View {
        card("认证通道延迟（UDP 61440 往返）") {
            Text("全局代理能不能用，取决于这条路——不是看模式。直连与经代理各测 3 次真实 challenge。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let sample = model.authLiveness {
                Text(sample.direct.description).font(.caption.monospaced())
                Text(sample.viaDefault.description).font(.caption.monospaced())
                Label(sample.verdict, systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.measureAuthLiveness()
            } label: {
                Label(model.diagnosticsBusy ? "测量中…" : "测认证通道", systemImage: "waveform.path.ecg.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(model.diagnosticsBusy)
        }
    }

    // MARK: Ping

    private var pingSection: some View {
        card("Ping（TCP 握手延迟）") {
            if model.pingResults.isEmpty {
                Text("点下方「开始 Ping」测一下网关/公网的往返延迟；同时对比走 VPN 的额外延迟。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.pingResults, id: \.host) { summary in
                    Text(summary.description).font(.caption.monospaced())
                }
            }
            Button {
                model.runPing()
            } label: {
                Label(model.diagnosticsBusy ? "测量中…" : "开始 Ping", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)
            .disabled(model.diagnosticsBusy)
        }
    }

    // MARK: 测速

    private var speedSection: some View {
        card("测速（HTTP 下载，对比直连与 VPN）") {
            if model.speedResults.isEmpty {
                Text("会分别用「网口直连」和「当前默认出口（含 VPN）」各下载一次，单位 Mbps。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.speedResults, id: \.self) { result in
                    Text(result.description).font(.caption.monospaced())
                }
                if !model.speedResults.contains(where: { $0.boundInterface != nil }) {
                    Label("网口直连测速不可用：可能被校园网关限制，或该端点只允许走代理。",
                          systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button {
                model.runSpeedTest()
            } label: {
                Label(model.diagnosticsBusy ? "测速中…" : "开始测速", systemImage: "speedometer")
            }
            .buttonStyle(.bordered)
            .disabled(model.diagnosticsBusy)
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
            Button("复制全部") { model.copyNetworkDetail() }
                .buttonStyle(.bordered)
            Spacer()
            Button("关闭") { model.closeNetworkDetail() }
                .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: 小工具

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
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
