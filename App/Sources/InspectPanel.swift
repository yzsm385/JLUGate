import SwiftUI
import JLUGateCore
import JLUGateNet

/// 「网络体检」：出口 IP、Cloudflare、WebRTC、DNS、人机验证——结论贴着每个模块写。
struct InspectPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("体检的是**浏览器会走的那条路**：出口 IP、WebRTC、DNS 泄漏、人机验证可达性。")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 快捷排查：能不能上网 + 到底哪一层坏了
            VStack(alignment: .leading, spacing: 6) {
                Text("能不能上网（快捷排查）").font(.caption).bold()
                Button {
                    model.runReachability()
                } label: {
                    Label(model.reachabilityRunning ? "排查中…" : "开始排查", systemImage: "bolt.horizontal")
                }
                .buttonStyle(.bordered)
                .disabled(model.reachabilityRunning)

                ForEach(model.reachability.filter { !$0.isCampus }) { reachRow($0) }
                if model.reachability.contains(where: \.isCampus) {
                    Text("校内系统（只在校园网内可访问）")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .padding(.top, 2)
                    ForEach(model.reachability.filter(\.isCampus)) { reachRow($0) }
                }
                if let diagnosis = model.reachabilityDiagnosis {
                    Text(diagnosis.summary).font(.caption2).bold()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(diagnosis.action).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                model.runInspection()
            } label: {
                Label(model.inspectionRunning ? "检测中…" : "开始检测", systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.inspectionRunning)

            module("出口 IP", value: ipValue, hint: ipHint)
            module("Cloudflare", value: cloudflareValue, hint: cloudflareHint)
            module("WebRTC（STUN）", value: webRTCValue, hint: webRTCHint)
            module("DNS", value: dnsValue, hint: dnsHint)
            module("人机验证", value: captchaValue, hint: captchaHint)

            // IP 纯净度：住宅 or 机房
            module("出口 IP 纯净度",
                   value: model.ipReputation?.summary ?? "",
                   hint: purityHint)
            if let notes = model.ipReputation?.notes, !notes.isEmpty {
                ForEach(notes, id: \.self) { note in
                    Text("· " + note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 带宽三档
            VStack(alignment: .leading, spacing: 6) {
                Text("带宽（三档对比）").font(.caption).bold()
                if let direct = model.speedDirect {
                    speedRow("直连", direct)
                }
                if let viaDefault = model.speedViaDefault {
                    speedRow("默认出口（含代理）", viaDefault)
                }
                if let viaProxy = model.speedViaProxy {
                    speedRow("本地代理", viaProxy)
                }
                HStack(spacing: 6) {
                    TextField("本地代理 127.0.0.1:7890", text: Binding(
                        get: { model.speedProxy },
                        set: { model.speedProxy = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    Button(model.speedRunning ? "测速中…" : "测速") { model.runSpeedAll() }
                        .buttonStyle(.bordered)
                        .disabled(model.speedRunning)
                }
                Text("第三档用你本机住宅代理客户端的本地端口；只有直连/代理两档时留空即可。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let url = model.portalViewerURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("在浏览器中打开校园网门户", systemImage: "safari")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func reachRow(_ result: SiteResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.ok ? Color.green : Color.orange)
            Text(result.host).font(.caption2.monospaced())
            Spacer()
            Text(result.display).font(.caption2).foregroundStyle(.secondary)
            if let ms = result.milliseconds {
                Text("\(ms) ms").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func speedRow(_ label: String, _ result: SpeedResult) -> some View {
        HStack {
            Text(label).font(.caption2)
            Spacer()
            Text(Throughput.format(megabitsPerSecond: result.megabitsPerSecond))
                .font(.caption2.monospacedDigit())
        }
    }

    private var purityHint: String {
        if let reputation = model.ipReputation {
            switch reputation.kind {
            case .residential: return "住宅/运营商 IP：对 Claude、流媒体这类站点最友好"
            case .datacenter: return "机房 IP：很多站点会直接拒绝或要求人机验证"
            case .mobile: return "移动网络 IP：一般也能通过，但可能被限速"
            case .unknown: return "归属信息不足，无法判断类型"
            }
        }
        return "点上面的「开始检测」，会查出口 IP 的归属与类型（住宅 / 机房）"
    }

    private func module(_ title: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).bold()
            if !value.isEmpty {
                Text(value).font(.caption.monospaced()).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: 文案

    private var ipValue: String {
        let samples = model.inspection.publicIPs
        guard !samples.isEmpty else { return "" }
        return samples.map { "\($0.source): \($0.ip)" }.joined(separator: "\n")
    }

    private var ipHint: String {
        if model.inspection.publicIPs.isEmpty {
            return model.inspectionRunning ? "正在问不同网站「你看到我是谁」…" : "点「开始检测」，问几个网站同一个问题"
        }
        let local = model.interfaces.first(where: { $0.name == model.config.interfaceLock })?.ipv4
        let same = local.map { localIP in
            model.inspection.publicIPs.contains { $0.ip == localIP }
        } ?? false
        return InspectionVerdict.ipHint(country: model.inspection.cloudflare?.location,
                                        sameAsLocal: same)
    }

    private var cloudflareValue: String {
        guard let trace = model.inspection.cloudflare else { return "" }
        var parts: [String] = []
        if let ip = trace.ip { parts.append(ip) }
        if let location = trace.location { parts.append("地区 \(location)") }
        if let colo = trace.colo { parts.append("机房 \(colo)") }
        return parts.joined(separator: " · ")
    }

    private var cloudflareHint: String {
        guard model.inspection.cloudflare != nil else { return "看 Cloudflare 认为你从哪个国家/机房出来" }
        return "Cloudflare 是最会认「你从哪来」的服务之一；机房离你越近，通常越快"
    }

    private var webRTCValue: String {
        let sample = model.inspection.webRTC
        guard let sample else { return "" }
        guard let ip = sample.publicIP else { return "无回执（\(sample.server)）" }
        return "\(ip)\(sample.port.map { ":\($0)" } ?? "")"
    }

    private var webRTCHint: String {
        guard let sample = model.inspection.webRTC else {
            return "STUN 是浏览器 WebRTC 用来问「我的公网地址」的协议；这里用同样的方法问一次"
        }
        let local = model.interfaces.first(where: { $0.name == model.config.interfaceLock })?.ipv4
        return InspectionVerdict.webRTCHint(sample, localIP: local)
    }

    private var dnsValue: String {
        guard let dns = model.inspection.dns else { return "" }
        var lines: [String] = []
        if let resolver = dns.systemResolver { lines.append("系统 DNS: \(resolver)") }
        if let egress = dns.systemEgress { lines.append("系统解析出口: \(egress)") }
        if let publicEgress = dns.publicEgress { lines.append("8.8.8.8 出口: \(publicEgress)") }
        return lines.joined(separator: "\n")
    }

    private var dnsHint: String {
        guard let dns = model.inspection.dns else {
            return "DNS 泄漏的意思是：你以为走了代理，域名却还是本地运营商在解析"
        }
        return dns.summary + (dns.hijackSuspected ? "；另外有可疑劫持迹象（不存在的域名被解析出地址）" : "")
    }

    private var captchaValue: String {
        model.inspection.captcha.map { "\($0.name)：\($0.human)" }.joined(separator: "\n")
    }

    private var captchaHint: String {
        InspectionVerdict.captchaHint(model.inspection.captcha)
    }
}
