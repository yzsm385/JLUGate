import SwiftUI
import JLUGateCore
import JLUGateNet

/// 「网络体检」：出口 IP、Cloudflare、WebRTC、DNS、人机验证——结论贴着每个模块写。
struct InspectPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.t("P01"))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 重新体检：居中，放在「能不能上网」上面
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    model.runInspection()
                } label: {
                    Label(model.inspectionRunning ? Copy.t("P05") : Copy.t("P06"),
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.inspectionRunning)
                Spacer(minLength: 0)
            }

            // 快捷排查：能不能上网 + 到底哪一层坏了
            VStack(alignment: .leading, spacing: 6) {
                // 已经合并进「开始检测」：这里只显示结果，不再单独给按钮
                Text(Copy.t("P02")).font(.caption).bold()
                if model.reachability.isEmpty {
                    Text(Copy.t("P03"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(model.reachability.filter { !$0.isCampus }) { reachRow($0) }
                if model.reachability.contains(where: \.isCampus) {
                    Text(Copy.t("P04"))
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

            egressIPModule
            module("WebRTC（STUN）", timingKey: "webrtc", value: webRTCValue, hint: webRTCHint)
            module("DNS", timingKey: "dns", value: dnsValue, hint: dnsHint)
            captchaModule

            // 带宽三档：随体检自动测，不再单独放「测速」按钮。
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Copy.t("P12")).font(.caption).bold()
                    if model.speedRunning {
                        Text(Copy.t("P17"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if let direct = model.speedDirect {
                    speedRow(Copy.t("P13"), direct)
                }
                if let viaDefault = model.speedViaDefault {
                    speedRow(Copy.t("P14"), viaDefault)
                }
                if let viaProxy = model.speedViaProxy {
                    speedRow(Copy.t("P15"), viaProxy)
                }
                if !model.speedRunning, model.speedDirect != nil {
                    Text(model.speedProxy.isEmpty
                         ? Copy.t("P19")
                         : Copy.f("P20", model.detectedProxy?.label ?? "本地代理", model.speedProxy))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let url = model.portalViewerURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(Copy.t("P21"), systemImage: "safari")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            // 进入体检就自动开始；按钮只当"重试"
            if !model.inspectionRunning {
                model.runInspection()
            }
        }
    }

    private func reachRow(_ result: SiteResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.ok ? Color.green : Color.orange)
            Text(result.host).font(.caption2.monospaced())
            if !result.accessNote.isEmpty {
                Text(result.accessNote)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
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
            case .residential: return Copy.t("P22")
            case .datacenter: return Copy.t("P23")
            case .mobile: return Copy.t("P24")
            case .unknown: return Copy.t("P25")
            }
        }
        return Copy.t("P26")
    }

    private func module(_ title: String, timingKey: String? = nil,
                        value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).font(.caption).bold()
                if let key = timingKey, let ms = model.inspectionTimings[key] {
                    Text("\(ms) ms").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
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

    private var ipValueWithFlag: String {
        let base = ipValue
        guard let country = model.geoConsensus?.country ?? model.inspection.cloudflare?.location,
              let flag = CountryFlag.emoji(for: country) else { return base }
        return "\(flag) \(base)"
    }

    private var ipHint: String {
        if model.inspection.publicIPs.isEmpty {
            return model.inspectionRunning ? Copy.t("P27") : Copy.t("P28")
        }
        let local = model.interfaces.first(where: { $0.name == model.config.interfaceLock })?.ipv4
        let same = local.map { localIP in
            model.inspection.publicIPs.contains { $0.ip == localIP }
        } ?? false
        return InspectionVerdict.ipHint(country: model.inspection.cloudflare?.location,
                                        sameAsLocal: same)
    }

    /// 出口 IP：把「IP 结果」和「纯净度/归属」合并成一张卡，
    /// 不再让 Cloudflare、纯净度、多源归属各写一遍同样的结论。
    private var egressIPModule: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(Copy.t("P07")).font(.caption).bold()
                if let ms = model.inspectionTimings["ip"] {
                    Text("\(ms) ms").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            if !ipValueWithFlag.isEmpty {
                Text(ipValueWithFlag)
                    .font(.caption.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reputation = model.ipReputation {
                HStack(spacing: 6) {
                    // 不再重复国旗：卡头已经有一个代表代理出口的旗；只有国家不同才在
                    // 下面（国内出口）单独显示旗。
                    Text(reputation.kindTitle).font(.caption)
                    if reputation.proxy == true {
                        Text(Copy.t("P30")).font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
                let place = [reputation.city, reputation.region, reputation.country]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
                if !place.isEmpty {
                    purityLine(Copy.t("P31"), place)
                }
                if let who = [reputation.isp, reputation.org].compactMap({ $0 }).first {
                    purityLine(Copy.t("P32"), who)
                }
                if let asn = reputation.asn { purityLine("ASN", asn) }
                purityLine(Copy.t("P33"),
                           reputation.kindTitle + (reputation.hosting == true ? Copy.t("P34") : ""))
                ForEach(Array(reputation.notes.enumerated()), id: \.offset) { _, note in
                    purityLine(Copy.t("P35"), note)
                }
            } else if model.inspectionRunning {
                Text("检测中…").font(.caption2).foregroundStyle(.secondary)
            }
            if let china = model.inspection.chinaIP,
               !model.inspection.publicIPs.contains(where: { $0.ip == china }) {
                HStack(spacing: 6) {
                    let different = (model.inspection.chinaCountry ?? "").uppercased()
                        != (proxyCountry ?? "").uppercased()
                    if different, let flag = CountryFlag.emoji(for: model.inspection.chinaCountry) {
                        Text(flag)
                    }
                    Text("国内出口 \(china)")
                        .font(.caption.monospaced())
                    Spacer(minLength: 0)
                    if different, let country = model.inspection.chinaCountry {
                        // 左边已经有一个旗了；这里只补国家代码，避免同一行两个 🇨🇳。
                        Text(country.uppercased())
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            let latency = latencyRows
            if !latency.isEmpty || model.authLivenessRunning || model.pingRunning {
                Divider().opacity(0.3)
                HStack(spacing: 6) {
                    Text("链路延迟").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if model.authLivenessRunning || model.pingRunning {
                        Text(Copy.t("P05")).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                ForEach(Array(latency.enumerated()), id: \.offset) { _, row in
                    latencyRow(row.label, row.value)
                }
                if let verdict = model.authLiveness?.verdict {
                    Text(verdict)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(egressHint)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var proxyCountry: String? {
        model.geoConsensus?.country
            ?? model.inspection.cloudflare?.location
            ?? model.ipReputation?.country
    }

    private var egressHint: String {
        var parts = [ipHint]
        if model.ipReputation != nil {
            parts.append(purityHint)
        }
        if let consensus = model.geoConsensus, consensus.countryDisagreement {
            parts.append(Copy.f("P10", consensus.countries.joined(separator: " / ")))
        }
        return parts.joined(separator: "\n")
    }

    /// 把直连/默认出口两次 Ping 合成一行，右侧数值，像人机验证那样分列。
    private var latencyRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let sample = model.authLiveness {
            rows.append(("认证通道", latencyText(sample.direct, sample.viaDefault)))
        }
        let ping = model.pingResults
        let viaPrefix = Copy.t("B515")
        var i = 0
        while i < ping.count {
            let direct = ping[i]
            var via: PingSummary?
            if i + 1 < ping.count, ping[i + 1].host.hasPrefix(viaPrefix) {
                via = ping[i + 1]
                i += 2
            } else {
                i += 1
            }
            let label = direct.host.split(separator: " ").first.map(String.init) ?? direct.host
            rows.append((label, latencyText(direct, via)))
        }
        return rows
    }

    private func latencyText(_ direct: PingSummary, _ via: PingSummary?) -> String {
        let d = direct.average.map { String(format: "%.0f ms", $0) } ?? "无回执"
        var text = "直连 \(d)"
        if let via {
            let v = via.average.map { String(format: "%.0f ms", $0) } ?? "无回执"
            text += " / 默认 \(v)"
            let loss = max(direct.loss, via.loss)
            if loss > 0 { text += String(format: " · 丢包 %.0f%%", loss * 100) }
        } else if direct.loss > 0 {
            text += String(format: " · 丢包 %.0f%%", direct.loss * 100)
        }
        return text
    }

    private func latencyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func purityLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // 30pt 连「归属运营商 (ASN)」都放不下，标签会一字一行地竖着排；
            // 给到和主面板明细一样的 96pt，长标签允许在栏内折行。
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
                .frame(width: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var webRTCValue: String {
        let sample = model.inspection.webRTC
        guard let sample else { return "" }
        guard let ip = sample.publicIP else { return Copy.f("P41", sample.server) }
        return "\(ip)\(sample.port.map { ":\($0)" } ?? "")"
    }

    private var webRTCHint: String {
        guard let sample = model.inspection.webRTC else {
            return Copy.t("P42")
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
            return Copy.t("P43")
        }
        var text: String
        if let alignment = model.dnsAlignment {
            // 与 IP 出口的国家对照；和 dns.summary 二选一，避免同一件事讲两遍。
            text = alignment.explanation
                + "  " + CountryFlag.label(alignment.ipCountry)
                + " / " + CountryFlag.label(alignment.dnsCountry)
        } else {
            text = dns.summary
        }
        if dns.hijackSuspected { text += Copy.t("P44") }
        return text
    }

    /// 人机验证：左边是站点名，右边是结论；中间留空，不要挤在一起。
    private var captchaModule: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(Copy.t("P08")).font(.caption).bold()
                if let ms = model.inspectionTimings["captcha"] {
                    Text("\(ms) ms").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            if model.inspection.captcha.isEmpty {
                Text(model.inspectionRunning ? Copy.t("P05") : Copy.t("P60"))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(model.inspection.captcha) { check in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(check.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(check.human)
                            .font(.caption.monospaced())
                            .foregroundStyle(check.state == .ok ? Color.primary : Color.orange)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            Text(captchaHint)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var captchaHint: String {
        InspectionVerdict.captchaHint(model.inspection.captcha)
    }
}
