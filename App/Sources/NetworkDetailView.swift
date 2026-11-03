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
                    vpnSection
                    interfaceSection
                    routeSection
                    pingSection
                    speedSection
                    glossarySection
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 620)
        .onAppear { model.refreshNetworkDetail() }
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
                .buttonStyle(.glass)
        }
        .padding(16)
    }

    private var subtitle: String {
        guard let snapshot else { return "正在读取…" }
        let vpn = snapshot.vpnIsActive ? "VPN/TUN 已接管" : "VPN/TUN 未接管"
        let dns = snapshot.dnsLooksHijacked ? " · DNS 被代理劫持" : ""
        return "\(vpn)\(dns)"
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
            .buttonStyle(.glass)
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
            .buttonStyle(.glass)
            .disabled(model.diagnosticsBusy)
        }
    }

    // MARK: 术语解释

    private var glossarySection: some View {
        card("这些字段是什么意思") {
            ForEach(FieldGuide.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.term).font(.caption.bold())
                    Text(entry.explanation).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack {
            Button("复制全部") { model.copyNetworkDetail() }
                .buttonStyle(.glass)
            Spacer()
            Button("关闭") { model.closeNetworkDetail() }
                .buttonStyle(.glass)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
