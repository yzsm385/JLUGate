import SwiftUI
import JLUGateCore
import JLUGateNet

/// 设置页：账号 / 链路 / 手填静态网络参数 / 服务器 / 自启。
///
/// 表单**不做自动填充**：静态地址是学校按端口分配的，只能人工照抄（PLAN §9.1）。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Draft()
    @State private var saved = false

    struct Draft {
        var account = ""
        var password = ""
        var link = "auto"
        var channel = "bsd"
        var server = "10.100.61.3"
        var serverPort = "61440"
        var localPort = "61440"
        var ip = ""
        var mask = ""
        var gateway = ""
        var dns = ""
        var registeredMAC = ""
        var launchAtLogin = true
        var autoDetect = true
        var autoConnect = true
        var portalEntry = ""
        var helperAuthorized = false
        var useRegisteredMACForAuth = false
        var compatibilityMode = false
    }

    var body: some View {
        Form {
            // 新生打开设置第一眼就能看到：去哪儿查自己的账号 / IP / 网费。
            Section {
                SelfServiceGuideCard(link: draft.link)
            } header: {
                Label("新生 / 第一次用", systemImage: "questionmark.bubble")
            }

            Section("账号") {
                TextField("学校邮箱前缀（如 zhangcyy2122 / zhangshanwu）", text: $draft.account)
                SecureField("密码（存 Keychain）", text: $draft.password)
                if let saved = model.storedPasswordSummary {
                    Text("留空 = 继续用已保存的密码（\(saved)）")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("链路") {
                Picker("接入方式", selection: $draft.link) {
                    Text("自动").tag("auto")
                    Text("有线").tag("wired")
                    Text("JLU.PC").tag("jluPC")
                    Text("JLU.WIFI").tag("jluWiFi")
                }
                Label("Wi-Fi 名字要一模一样：JLU.PC / JLU.WIFI（大写、中间是一个点）；"
                      + "同名网络先确认是不是学校的，可疑网络里别输账号。",
                      systemImage: "exclamationmark.shield")
                    .font(.system(size: 9)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("通道实现", selection: $draft.channel) {
                    Text("BSD（默认，最接近官方客户端）").tag("bsd")
                    Text("NW（系统网络框架）").tag("nw")
                }
                Text("BSD：原始 socket，能精确绑定源端口 61440 和网卡（IP_BOUND_IF）；"
                     + "NW：走 Network.framework，受系统路径管理。两者发的是同样的 UDP 包，"
                     + "默认用 BSD，遇到系统限制再换 NW。")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text("固定网络参数（只用于有线 / JLU.PC）")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if draft.link == "jluWiFi" {
                    Label("当前选的是 JLU.WIFI：动态分配地址 + 网页认证，下面这些静态参数都不用填。",
                          systemImage: "wifi")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    LabeledAddressField(title: "IP", kind: .ipv4, text: $draft.ip,
                                        hint: "学校分给你的固定地址，按通知单照抄（不是 DHCP 分到的）",
                                        onSubmit: focusNextField)
                        .onChange(of: draft.ip) { _, newValue in
                            let parts = newValue.split(separator: "·").map(String.init)
                            guard parts.count == 4 else { return }
                            if draft.mask.isEmpty { draft.mask = "255·255·255·0" }
                            if draft.gateway.isEmpty {
                                draft.gateway = "\(parts[0])·\(parts[1])·\(parts[2])·254"
                            }
                        }
                    LabeledAddressField(title: "子网掩码", kind: .ipv4, text: $draft.mask,
                                        hint: "一般是 255.255.255.0",
                                        onSubmit: focusNextField)
                    LabeledAddressField(title: "网关", kind: .ipv4, text: $draft.gateway,
                                        hint: "同网段的第一跳，通常是 x.x.x.254",
                                        onSubmit: focusNextField)
                    LabeledAddressField(title: "DNS", kind: .ipv4, text: Binding(
                        get: { draft.dns.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "" },
                        set: { draft.dns = $0 }),
                                        hint: "校内 10.10.10.10；校外可换 223.5.5.5")
                    LabeledAddressField(title: "登记 MAC", kind: .mac, text: $draft.registeredMAC,
                                        hint: "学校登记的那块网卡的物理地址（不是系统随机 MAC）",
                                        onSubmit: save)
                }
                Toggle("兼容模式：关闭液态玻璃（虚拟机/老显卡上更稳，重启生效）", isOn: $draft.compatibilityMode)
                Toggle("系统用了私有/随机 MAC 时，用登记的 MAC 认证（高级）", isOn: $draft.useRegisteredMACForAuth)
                Text("只影响认证报文里的 MAC 字段，不改网卡本身。优选方案仍是到系统设置里把「私有地址」关掉。")
                    .font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text("静态网络参数")
            }

            Section("系统当前值（仅供核对）") {
                ForEach(model.orderedInterfaces, id: \.name) { item in
                    Text("\(item.name)：\(item.ipv4 ?? "无 IPv4")  当前 MAC \(item.mac ?? "—")  出厂 MAC \(item.hardwareMAC ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("路由：\(model.routeSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("网卡") {
                Text(model.interfaceMatchingSummary)
                    .font(.caption2)
                    .foregroundStyle(model.interfaceCandidates.contains(where: {
                        $0.matches(model.config.currentProfile?.registeredMAC.flatMap(MACAddress.init))
                    }) ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("使用哪块网卡", selection: Binding(
                    get: { model.config.interfaceLock ?? "" },
                    set: { model.selectInterface($0.isEmpty ? nil : $0) })) {
                    Text("自动（按 MAC 认）").tag("")
                    ForEach(model.interfaceCandidates) { candidate in
                        Text("\(candidate.name)  \(candidate.macForAuthentication ?? "—")")
                            .tag(candidate.name)
                    }
                }

                Button("按登记 MAC 自动选一次") { model.autoSelectInterface() }
                    .buttonStyle(.bordered)
            }

            Section("链路探测") {
                Toggle("启动时自动连接（记住账号密码后不再打扰）", isOn: $draft.autoConnect)
                Toggle("自动探测（发 1 个 challenge 判断是不是校园网）", isOn: $draft.autoDetect)
                Text("关掉后只做 204 探针，不会主动向校园网关发任何认证包。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("网页认证入口 URL（可留空自动获取）", text: $draft.portalEntry)
            }

            Section("路由保障") {
                Text("当前：\(routeGuardText)")
                    .font(.caption)
                Toggle("允许后台组件加 -ifscope 直连路由（需管理员授权）", isOn: $draft.helperAuthorized)
                    .disabled(true)
                Text("后台 helper 属于 M2.5，尚未随本版本提供；未授权时会退化成“给一条可复制的命令”。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("更新") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("检查更新") { model.checkForUpdates(force: true) }
                            .disabled(model.updateStatus == .checking)
                        Text("当前版本 \(BuildInfo.version)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    updateStatusView
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("高级") {
                TextField("服务器", text: $draft.server)
                TextField("服务器端口", text: $draft.serverPort)
                TextField("本地端口（必须是 61440）", text: $draft.localPort)
                Toggle("开机自启", isOn: $draft.launchAtLogin)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("保存") { save() }
                            .buttonStyle(.borderedProminent)
                        if saved {
                            Label("已保存", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("关闭") { model.closeSettings() }
                            .buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("读系统值") {
                                model.refreshDiagnostics()
                                let suggestion = model.applySystemParameters()
                                if draft.registeredMAC.isEmpty,
                                   let hardware = model.hardwareMACForCurrentInterface() {
                                    draft.registeredMAC = hardware
                                }
                                if suggestion.hasUsableValues { load(); saved = true }
                                else { model.recentLog.insert(suggestion.reason, at: 0) }
                            }
                            Button("重新检测") { model.refreshDiagnostics() }
                        }
                        HStack(spacing: 8) {
                            Button("导入参数卡") {
                                if model.importConfigCardFromClipboard() {
                                    load()
                                    saved = true
                                }
                            }
                            Button("清空网络参数") {
                                draft.ip = ""; draft.mask = ""; draft.gateway = ""
                                draft.dns = ""; draft.registeredMAC = ""
                                model.clearNetworkParameters()
                                saved = true
                            }
                        }
                        Button("删除已保存的密码") {
                            model.clearSavedPassword()
                            draft.password = ""
                            saved = true
                        }
                        Button("重置本机配置…") { model.resetLocalConfiguration() }
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { Task { @MainActor in load() } }
        .onChange(of: draft.account) { _, newValue in
            // 切账号就载入该账号自己的档案（PLAN M4 验收："切换账号时能按账号载入各自档案"）
            guard newValue != model.config.account else { return }
            guard let profile = model.config.accounts[newValue] else {
                // 这个账号还没有档案 → 清空，让用户从头填
                draft.ip = ""
                draft.mask = ""
                draft.gateway = ""
                draft.dns = ""
                draft.registeredMAC = ""
                draft.password = CredentialStore.password(for: newValue) ?? ""
                return
            }
            draft.ip = profile.ip ?? ""
            draft.mask = profile.mask ?? ""
            draft.gateway = profile.gateway ?? ""
            draft.dns = profile.dns.joined(separator: ",")
            draft.registeredMAC = profile.registeredMAC ?? ""
            draft.password = CredentialStore.password(for: newValue) ?? ""
        }
    }

    private func focusNextField() {
        NSApp.keyWindow?.selectNextKeyView(nil)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch model.updateStatus {
        case .idle:
            Text("").font(.caption)
        case .checking:
            Label("检查中…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        case .upToDate:
            Label("已是最新", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
        case .available(let tag, let name, let page, let asset):
            VStack(alignment: .leading, spacing: 3) {
                Label("有新版本 \(tag)", systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Button("下载并安装") {
                        model.installAvailableUpdate(page: page, asset: asset)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("仅下载") {
                        if let url = asset ?? page { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link).font(.caption)
                }
                if let message = model.updateInstallMessage {
                    Text(message).font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message).font(.caption2).foregroundStyle(.orange)
        }
    }

    private func load() {
        let config = model.config
        let profile = config.currentProfile
        draft.account = config.account
        // 内存里没有也去本机凭据里取一次，别让用户重输
        draft.password = model.password.isEmpty
            ? (CredentialStore.password(for: config.account) ?? "")
            : model.password
        draft.link = config.link
        draft.channel = config.channel
        draft.server = config.server
        draft.serverPort = String(config.serverPort)
        draft.localPort = String(config.localPort)
        draft.ip = profile?.ip ?? ""
        draft.mask = profile?.mask ?? ""
        draft.gateway = profile?.gateway ?? ""
        draft.dns = (profile?.dns ?? []).joined(separator: ",")
        draft.registeredMAC = profile?.registeredMAC ?? ""
        draft.launchAtLogin = config.launchAtLogin
        draft.autoDetect = config.autoDetect
        draft.autoConnect = config.autoConnect
        draft.portalEntry = config.portal.entryURL ?? ""
        draft.helperAuthorized = config.routeGuard.helperAuthorized == true
        draft.useRegisteredMACForAuth = config.useRegisteredMACForAuth
        draft.compatibilityMode = config.compatibilityMode
    }

    private var routeGuardText: String {
        switch model.routeGuarantee {
        case .direct(let interface): "A 层 · 出口就是 \(interface)，零特权可用"
        case .helper(let interface, _, _): "B 层 · 由 helper 给 \(interface) 加 /32 路由"
        case .manual(_, let interface): "C 层 · 需要手动给 \(interface) 加一条路由"
        case .noRoute: "拿不到路由（接口没起来或没有到服务器的路由）"
        case nil: "未检测"
        }
    }

    private func save() {
        var config = model.config
        let hadProfileForAccount = config.accounts[draft.account] != nil
        config.account = draft.account
        config.link = draft.link
        config.channel = draft.channel
        config.server = draft.server
        config.serverPort = Int(draft.serverPort) ?? 61440
        config.localPort = Int(draft.localPort) ?? 61440
        config.launchAtLogin = draft.launchAtLogin
        config.autoDetect = draft.autoDetect
        config.autoConnect = draft.autoConnect
        config.portal.entryURL = draft.portalEntry.isEmpty ? nil : draft.portalEntry
        config.routeGuard.helperAuthorized = draft.helperAuthorized
        config.useRegisteredMACForAuth = draft.useRegisteredMACForAuth
        config.compatibilityMode = draft.compatibilityMode

        let profile = AppConfig.NetworkProfile(
            ip: draft.ip.isEmpty ? nil : NetworkValidation.canonical(draft.ip),
            mask: draft.mask.isEmpty ? nil : NetworkValidation.canonical(draft.mask),
            gateway: draft.gateway.isEmpty ? nil : NetworkValidation.canonical(draft.gateway),
            dns: draft.dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            registeredMAC: draft.registeredMAC.isEmpty
                ? nil : NetworkValidation.canonicalMAC(draft.registeredMAC),
            interfaceHint: config.accounts[draft.account]?.interfaceHint,
            configuredAt: config.accounts[draft.account]?.configuredAt
                ?? ISO8601DateFormatter().string(from: .now))
        config.accounts[draft.account] = profile

        model.config = config
        // 密码框留空表示"沿用已保存的密码"，不要用空值覆盖
        if !draft.password.isEmpty { model.password = draft.password }
        model.persist(); model.refreshDiagnostics()
        if !hadProfileForAccount, config.link != "jluWiFi", (draft.ip.isEmpty || draft.mask.isEmpty) {
            // 新账号但地址没填全：只提示，不再弹一次"输入账号密码"（刚在设置里填过）
            model.recentLog.insert("有线/JLU.PC 还需要 IP、掩码等静态参数：可以点「用系统当前读数填入」", at: 0)
            FileLogger.shared.log("保存配置：地址不完整，等待用户补全")
        }
        if !draft.password.isEmpty, !DevOverrides.isEnabled {
            try? CredentialStore.save(password: draft.password, account: draft.account)
        }
        LoginItem.apply(enabled: draft.launchAtLogin)
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            saved = false
        }
    }
}
