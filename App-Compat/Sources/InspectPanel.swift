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
                    Text("校内系统（教务/通知仅校内；邮箱校内外都能开）")
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
                Label(model.inspectionRunning ? Copy.t("P05") : Copy.t("P06"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.inspectionRunning)

            module(Copy.t("P07"), timingKey: "ip", value: ipValueWithFlag, hint: ipHint)
            module("Cloudflare", timingKey: "cloudflare", value: cloudflareValue, hint: cloudflareHint)
            module("WebRTC（STUN）", timingKey: "webrtc", value: webRTCValue, hint: webRTCHint)
            module("DNS", timingKey: "dns", value: dnsValue, hint: dnsHint)
            module(Copy.t("P08"), timingKey: "captcha", value: captchaValue, hint: captchaHint)

            // IP 纯净度：住宅 or 机房
            purityModule
            if let consensus = model.geoConsensus {
                ForEach(consensus.samples) { sample in
                    HStack(spacing: 6) {
                        Text(sample.source).font(.system(size: 10)).frame(width: 66, alignment: .leading)
                        Text((CountryFlag.emoji(for: sample.country).map { $0 + " " } ?? "") + sample.short)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let bilibili = model.bilibiliObservation {
                    HStack(spacing: 6) {
                        Text("BiliBili").font(.system(size: 10)).frame(width: 66, alignment: .leading)
                        Text("\(model.bilibiliAddr ?? "-") · " + bilibili.short
                             + (model.bilibiliAddr == consensus.ip ? "" : Copy.t("P09")))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if consensus.countryDisagreement {
                    Text(Copy.f("P10", consensus.countries.joined(separator: " / ")))
                        .font(.system(size: 10)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let alignment = model.dnsAlignment {
                Text(Copy.t("P11") + alignment.explanation
                     + "  " + CountryFlag.label(alignment.ipCountry)
                     + " / " + CountryFlag.label(alignment.dnsCountry))
                    .font(.system(size: 10))
                    .foregroundStyle(alignment.verdict == .differentCountry ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notes = model.ipReputation?.notes, !notes.isEmpty {
                ForEach(notes, id: \.self) { note in
                    Text("· " + note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 带宽三档
            VStack(alignment: .leading, spacing: 6) {
                Text(Copy.t("P12")).font(.caption).bold()
                if let direct = model.speedDirect {
                    speedRow(Copy.t("P13"), direct)
                }
                if let viaDefault = model.speedViaDefault {
                    speedRow(Copy.t("P14"), viaDefault)
                }
                if let viaProxy = model.speedViaProxy {
                    speedRow(Copy.t("P15"), viaProxy)
                }
                HStack(spacing: 6) {
                    TextField(Copy.t("P16"), text: Binding(
                        get: { model.speedProxy },
                        set: { model.speedProxy = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    Button(model.speedRunning ? Copy.t("P17") : Copy.t("P18")) { model.runSpeedAll() }
                        .buttonStyle(.bordered)
                        .disabled(model.speedRunning)
                }
                Text(model.speedProxy.isEmpty
                     ? Copy.t("P19")
                     : Copy.f("P20", model.detectedProxy?.label ?? "本地代理", model.speedProxy))
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

    /// 纯净度：分行展示，不要全挤成一行
    @ViewBuilder
    private var purityModule: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(Copy.t("P29")).font(.caption).bold()
                Spacer(minLength: 0)
            }
            if let reputation = model.ipReputation {
                HStack(spacing: 6) {
                    if let flag = CountryFlag.emoji(for: reputation.country) { Text(flag) }
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
                purityLine(Copy.t("P33"), reputation.kindTitle + (reputation.hosting == true ? Copy.t("P34") : ""))
                ForEach(Array(reputation.notes.enumerated()), id: \.offset) { _, note in
                    purityLine(Copy.t("P35"), note)
                }
            } else {
                Text(model.inspectionRunning ? "检测中…" : Copy.t("P36")).font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(purityHint).font(.system(size: 9)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func purityLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .leading)
            Text(value).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cloudflareValue: String {
        guard let trace = model.inspection.cloudflare else { return "" }
        var parts: [String] = []
        if let ip = trace.ip {
            parts.append((CountryFlag.emoji(for: trace.location).map { $0 + " " } ?? "") + ip)
        }
        if let location = trace.location { parts.append(Copy.f("P37", location)) }
        if let colo = trace.colo { parts.append(Copy.f("P38", colo)) }
        return parts.joined(separator: " · ")
    }

    private var cloudflareHint: String {
        guard model.inspection.cloudflare != nil else { return Copy.t("P39") }
        return Copy.t("P40")
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
        return dns.summary + (dns.hijackSuspected ? Copy.t("P44") : "")
    }

    private var captchaValue: String {
        model.inspection.captcha.map { "\($0.name)：\($0.human)" }.joined(separator: "\n")
    }

    private var captchaHint: String {
        InspectionVerdict.captchaHint(model.inspection.captcha)
    }
}
