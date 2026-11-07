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
    @State private var showGuide = false

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
            // 第一次 / 还没填完：萌新指南顶在最上面。
            if !guideCanCollapse {
                Section {
                    SelfServiceGuideCard(link: draft.link)
                } header: {
                    Label(Copy.t("S01"), systemImage: "questionmark.bubble")
                }
            }

            Section(languageSectionTitle) {
                Picker(languagePickerTitle, selection: Binding(
                    get: { model.languageCode },
                    set: { model.setLanguage($0) })) {
                    Text(followSystemLabel).tag("system")
                    ForEach(CopyLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
            }

            if !LoginItem.isEnabled {
                Section(Copy.t("R18")) {
                    LoginItemGuide()
                        .padding(.vertical, 2)
                }
            }

            Section(Copy.t("S02")) {
                TextField(Copy.t("S03"), text: $draft.account)
                SecureField(Copy.t("S04"), text: $draft.password)
                if let saved = model.storedPasswordSummary {
                    Text(Copy.f("S05", saved))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(Copy.t("S06")) {
                Picker(Copy.t("S07"), selection: $draft.link) {
                    Text(Copy.t("S08")).tag("auto")
                    Text(Copy.t("S09")).tag("wired")
                    Text("JLU.PC").tag("jluPC")
                    Text("JLU.WIFI").tag("jluWiFi")
                }
                Label(Copy.t("S10")
                      + Copy.t("S11"),
                      systemImage: "exclamationmark.shield")
                    .font(.system(size: 9)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(Copy.t("S12"), selection: $draft.channel) {
                    Text(Copy.t("S13")).tag("bsd")
                    Text(Copy.t("S14")).tag("nw")
                }
                Text(Copy.t("S15")
                     + Copy.t("S16")
                     + Copy.t("S17"))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text(Copy.t("S18"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if draft.link == "jluWiFi" {
                    Label(Copy.t("S19"),
                          systemImage: "wifi")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    LabeledAddressField(title: "IP", kind: .ipv4, text: $draft.ip,
                                        hint: Copy.t("S20"),
                                        onSubmit: focusNextField)
                        .onChange(of: draft.ip) { _, newValue in
                            let parts = newValue.split(separator: "·").map(String.init)
                            guard parts.count == 4 else { return }
                            if draft.mask.isEmpty { draft.mask = "255·255·255·0" }
                            if draft.gateway.isEmpty {
                                draft.gateway = "\(parts[0])·\(parts[1])·\(parts[2])·254"
                            }
                        }
                    LabeledAddressField(title: Copy.t("S21"), kind: .ipv4, text: $draft.mask,
                                        hint: Copy.t("S22"),
                                        onSubmit: focusNextField)
                    LabeledAddressField(title: Copy.t("S23"), kind: .ipv4, text: $draft.gateway,
                                        hint: Copy.t("S24"),
                                        onSubmit: focusNextField)
                    LabeledAddressField(title: "DNS", kind: .ipv4, text: dnsPrimaryBinding,
                                        hint: Copy.t("S25"))
                    LabeledAddressField(title: Copy.t("S26"), kind: .mac, text: $draft.registeredMAC,
                                        hint: Copy.t("S27"),
                                        onSubmit: save)
                }
                Toggle(Copy.t("S28"), isOn: $draft.compatibilityMode)
                Toggle(Copy.t("S29"), isOn: $draft.useRegisteredMACForAuth)
                Text(Copy.t("S30"))
                    .font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text(Copy.t("S31"))
            }

            Section(Copy.t("S32")) {
                ForEach(model.orderedInterfaces, id: \.name) { item in
                    Text("\(item.name)：\(item.ipv4 ?? "无 IPv4")  当前 MAC \(item.mac ?? "—")  出厂 MAC \(item.hardwareMAC ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(Copy.f("S33", model.routeSummary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Copy.t("S34")) {
                Text(model.interfaceMatchingSummary)
                    .font(.caption2)
                    .foregroundStyle(model.interfaceCandidates.contains(where: {
                        $0.matches(model.config.currentProfile?.registeredMAC.flatMap(MACAddress.init))
                    }) ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(Copy.t("S35"), selection: Binding(
                    get: { model.config.interfaceLock ?? "" },
                    set: { model.selectInterface($0.isEmpty ? nil : $0) })) {
                    Text(Copy.t("S36")).tag("")
                    ForEach(model.interfaceCandidates) { candidate in
                        Text("\(candidate.name)  \(candidate.macForAuthentication ?? "—")")
                            .tag(candidate.name)
                    }
                }

                Button(Copy.t("S37")) { model.autoSelectInterface() }
                    .buttonStyle(.bordered)
            }

            Section(Copy.t("S38")) {
                Toggle(Copy.t("S39"), isOn: $draft.autoConnect)
                Toggle(Copy.t("S40"), isOn: $draft.autoDetect)
                Text(Copy.t("S41"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField(Copy.t("S42"), text: $draft.portalEntry)
            }

            Section(Copy.t("S43")) {
                Text(Copy.f("S44", routeGuardText))
                    .font(.caption)
                Toggle(Copy.t("S45"), isOn: $draft.helperAuthorized)
                    .disabled(true)
                Text(Copy.t("S46"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section(Copy.t("S47")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button(Copy.t("S48")) { model.checkForUpdates(force: true) }
                            .disabled(model.updateStatus == .checking)
                        Text(Copy.f("S49", BuildInfo.version))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    updateStatusView
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(Copy.t("S50")) {
                TextField(Copy.t("S51"), text: $draft.server)
                TextField(Copy.t("S52"), text: $draft.serverPort)
                TextField(Copy.t("S53"), text: $draft.localPort)
                Toggle(Copy.t("S54"), isOn: $draft.launchAtLogin)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(Copy.t("S55")) { save() }
                            .buttonStyle(.borderedProminent)
                        if saved {
                            Label(Copy.t("S56"), systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button(Copy.t("S57")) { model.closeSettings() }
                            .buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(Copy.t("S58")) {
                                model.refreshDiagnostics()
                                let suggestion = model.applySystemParameters()
                                if draft.registeredMAC.isEmpty,
                                   let hardware = model.hardwareMACForCurrentInterface() {
                                    draft.registeredMAC = hardware
                                }
                                if suggestion.hasUsableValues { load(); saved = true }
                                else { model.recentLog.insert(suggestion.reason, at: 0) }
                            }
                            Button(Copy.t("S59")) { model.refreshDiagnostics() }
                        }
                        HStack(spacing: 8) {
                            Button(Copy.t("S60")) {
                                if model.importConfigCardFromClipboard() {
                                    load()
                                    saved = true
                                }
                            }
                            Button(Copy.t("S61")) {
                                draft.ip = ""; draft.mask = ""; draft.gateway = ""
                                draft.dns = ""; draft.registeredMAC = ""
                                model.clearNetworkParameters()
                                saved = true
                            }
                        }
                        Button(Copy.t("S62")) {
                            model.clearSavedPassword()
                            draft.password = ""
                            saved = true
                        }
                        Button(Copy.t("S63")) { model.resetLocalConfiguration() }
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // 参数填完、成功连过：指南收到底部，需要时再展开。
            if guideCanCollapse {
                Section {
                    DisclosureGroup(isExpanded: $showGuide) {
                        SelfServiceGuideCard(link: draft.link)
                            .padding(.top, 6)
                    } label: {
                        Label(Copy.t("S01"), systemImage: "questionmark.bubble")
                    }
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

    /// 只编辑首选 DNS，保留逗号后面的备选
    private var dnsPrimaryBinding: Binding<String> {
        Binding(
            get: { draft.dns.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "" },
            set: { newValue in
                var parts = draft.dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.isEmpty { parts = [""] }
                parts[0] = newValue
                draft.dns = parts.joined(separator: ",")
            })
    }

    /// 已经填完静态参数并成功连接过 → 指南收到底部折叠；
    /// 第一次用、或参数还没填全 → 继续顶在最上面。
    private var guideCanCollapse: Bool {
        let profile = model.config.currentProfile
        let completeStatic = profile?.ip != nil && profile?.mask != nil
            && profile?.gateway != nil && profile?.registeredMAC != nil
        let hasAnyStatic = profile?.ip != nil || profile?.mask != nil
            || profile?.gateway != nil || profile?.registeredMAC != nil
        let staticReady: Bool
        switch model.config.link {
        case "wired", "jluPC": staticReady = completeStatic
        case "jluWiFi": staticReady = true
        default: staticReady = hasAnyStatic ? completeStatic : true
        }
        let connected = model.config.lastSuccessfulLogin != nil
            || model.state.isOnline
            || model.observingExistingSession
        return staticReady && connected
    }

    // MARK: 语言

    private var languageSectionTitle: String {
        switch Copy.language {
        case .zhHans: "语言"
        case .zhHant: "語言"
        case .en: "Language"
        }
    }

    private var languagePickerTitle: String {
        switch Copy.language {
        case .zhHans: "界面语言"
        case .zhHant: "介面語言"
        case .en: "Interface language"
        }
    }

    private var followSystemLabel: String {
        switch Copy.language {
        case .zhHans: "跟随系统"
        case .zhHant: "跟隨系統"
        case .en: "Follow system"
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
            Label(Copy.t("S64"), systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        case .upToDate:
            Label(Copy.t("S65"), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
        case .available(let tag, let name, let page, let asset):
            VStack(alignment: .leading, spacing: 3) {
                Label(Copy.f("S66", tag), systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Button(Copy.t("S67")) {
                        model.installAvailableUpdate(page: page, asset: asset)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(Copy.t("S68")) {
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
        case .direct(let interface): Copy.f("S69", interface)
        case .helper(let interface, _, _): Copy.f("S70", interface)
        case .manual(_, let interface): Copy.f("S71", interface)
        case .noRoute: Copy.t("S72")
        case nil: Copy.t("S73")
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


/// 开机自启的说明：状态 + 步骤 + 直接跳系统设置
struct LoginItemGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LoginItem.statusText)
                .font(.system(size: 9))
                .foregroundStyle(LoginItem.isEnabled ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.t("R19"))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.t("R26"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Button(Copy.t("R24")) { LoginItem.openSystemSettings() }
                    .controlSize(.small)
                if !LoginItem.isEnabled, AppIdentity.isInstalled {
                    Button(Copy.t("R25")) { LoginItem.enableNow() }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
