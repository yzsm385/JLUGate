import SwiftUI
import JLUGateCore
import JLUGateNet

/// 首次启动向导（PLAN §9.1）。
///
/// 顺序按用户的真实心智模型来：
/// 1. **账号密码**（三条链路共用一份，填一次就记住）；
/// 2. **接入方式**（有线 / JLU.PC / JLU.WIFI / 自动）；
/// 3. **网络参数**——只有选了有线或 JLU.PC、且这台机器上还没填过完整参数时才出现；
///    填过就跳过，绝不再问第二遍。
struct WizardView: View {
    private enum Step: Int, CaseIterable {
        case credentials
        case link
        case network
    }

    @Environment(AppModel.self) private var model

    @State private var step: Step = .credentials
    @State private var account = ""
    @State private var password = ""
    /// 重新输入密码时的第二次确认（避免输入法全角/多字符导致"看着一样其实不一样"）
    @State private var passwordConfirm = ""
    @State private var link = "auto"
    @State private var ip = ""
    @State private var mask = ""
    @State private var gateway = ""
    @State private var dns = ""
    @State private var mac = ""
    @State private var errorText: String?
    @State private var hasSavedProfile = false
    @State private var hasSavedPassword = false
    @State private var savedPasswordVerified = false
    @State private var suggestionNote: String?
    @State private var isSuggestionTrustworthy = false

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {
            header

            // 向导是**独立窗口**：不用 GlassEffectContainer / glassEffectID（真机上会在
            // AppKit 显示周期抛异常崩溃），卡片改普通材质。
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    switch step {
                    case .credentials: credentialsStep
                    case .link: linkStep
                    case .network: networkStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .jluGlassCard(cornerRadius: 24)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: step) { _, newStep in
            if newStep == .network, ip.isEmpty, mask.isEmpty {
                fillFromSystem()
            }
        }
        .onAppear {
            Task { @MainActor in
                load()
                if model.wizardStartsAtNetwork {
                    step = .network
                    link = "wired"
                    model.wizardStartsAtNetwork = false
                }
                if step == .network, ip.isEmpty, mask.isEmpty {
                    fillFromSystem()
                }
                if DevOverrides.wizardStartsAtNetwork {
                    account = "20230001"
                    password = "test-pass-2024"
                    link = "wired"
                    ip = "203.0.113.11"
                    mask = "255.255.255.0"
                    gateway = "203.0.113.1"
                    dns = "10.10.10.10"
                    mac = "02:00:00:00:00:01"
                    step = .network
                }
                FileLogger.shared.log("wizard: 打开，step=\(step) link=\(link) account=\(account.isEmpty ? "-" : account)")
            }
        }
        .onChange(of: step) { _, newValue in
            FileLogger.shared.log("wizard: 进入步骤 \(newValue)")
        }
        .onChange(of: link) { _, newValue in
            FileLogger.shared.log("wizard: 选择链路 \(newValue)（needsNetwork=\(needsNetworkStep)）")
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.t("W01"))
                .font(.title2.bold())
            Text(Copy.f("W02", step.rawValue + 1, Step.allCases.count, stepTitle))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepTitle: String {
        switch step {
        case .credentials: Copy.t("W03")
        case .link: Copy.t("W04")
        case .network: Copy.t("W05")
        }
    }

    // MARK: 步骤：账号密码

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Copy.t("W06"),
                  systemImage: "person.badge.key")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(Copy.t("W07"), text: $account)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)

            // 账号就是邮箱 @mails.jlu.edu.cn 前面那一段；跟着输入实时给出判断
            if !account.isEmpty {
                let analysis = AccountFormat.analyze(account)
                Label(analysis.hint, systemImage: analysis.isLikelyValid ? "checkmark.circle" : "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(analysis.isLikelyValid ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(AccountFormat.guidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasSavedPassword, password.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.requirePasswordReentry
                          ? Copy.t("W08")
                          : (savedPasswordVerified ? Copy.t("W09")
                                                   : Copy.t("W10")),
                          systemImage: (savedPasswordVerified && !model.requirePasswordReentry)
                            ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle((savedPasswordVerified && !model.requirePasswordReentry)
                                         ? Color.secondary : Color.orange)
                    HStack(spacing: 8) {
                        if !model.requirePasswordReentry {
                            Button(Copy.t("W11")) {
                                if let stored = CredentialStore.password(for: account),
                                   !stored.isEmpty {
                                    password = stored
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(Copy.t("W12")) {
                            hasSavedPassword = false      // 收起这块，直接输入新的
                            password = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            SecureField(Copy.t("W13"), text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)

            if model.requirePasswordReentry, !password.isEmpty {
                SecureField(Copy.t("W14"), text: $passwordConfirm)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                if !passwordConfirm.isEmpty, passwordConfirm != password {
                    Label(Copy.t("W15"),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text(Copy.f("W16", PasswordFingerprint.describe(password)))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }

            Label(keychainNote, systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // 新生最容易错的地方：以为所有地方都是同一个密码。
            // 这里填的是统一身份认证那套；自助平台查 IP 用的是校园卡号 + 6 位 V 卡密码。
            SelfServiceHintRow(text: Copy.t("W17"))
        }
    }

    private var keychainNote: String {
        switch CredentialStore.backend {
        case .keychain: Copy.t("W18")
        case .file: Copy.t("W19")
        }
    }

    // MARK: 步骤：接入方式

    private var linkStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 不用 Picker(.radioGroup)：它在玻璃容器里点选时会触发渲染问题，
            // 换成普通按钮行，行为一致但更稳。
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.linkOptions, id: \.value) { option in
                    Button {
                        link = option.value
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: link == option.value ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(link == option.value ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                Text(option.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(hintForLink)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 认名字：学校的无线只有这两个，名字要一模一样；同名热点可能是别人伪装的
            Label(Copy.t("W20")
                  + Copy.t("W21"),
                  systemImage: "exclamationmark.shield")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            if !model.interfaces.isEmpty {
                Text(Copy.f("W22", model.interfaces.filter(\.isUsableForAuthentication).map(\.name).joined(separator: "、")))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private struct LinkOption: Identifiable {
        let value: String
        let title: String
        let detail: String
        var id: String { value }
    }

    private static let linkOptions: [LinkOption] = [
        LinkOption(value: "auto", title: Copy.t("W23"), detail: Copy.t("W24")),
        LinkOption(value: "wired", title: Copy.t("W25"), detail: Copy.t("W26")),
        LinkOption(value: "jluPC", title: Copy.t("W27"), detail: Copy.t("W28")),
        LinkOption(value: "jluWiFi", title: Copy.t("W29"), detail: Copy.t("W30")),
    ]

    private var hintForLink: String {
        switch link {
        case "wired": Copy.t("W31")
        case "jluPC": JLUAccessPolicy.jluPCHint
        case "jluWiFi": Copy.t("W32")
        default: Copy.t("W33")
        }
    }

    // MARK: 步骤：网络参数

    private var needsNetworkStep: Bool {
        // 决策逻辑放在 Core 里单测过：先账号 → 再方式 → 需要且没填过才问地址
        WizardPolicy.steps(link: link, profileIsComplete: hasSavedNetworkParameters).contains(.network)
    }

    private var hasSavedNetworkParameters: Bool {
        let profile = model.config.accounts[account] ?? model.config.currentProfile
        return WizardPolicy.profileIsComplete(
            ip: profile?.ip, mask: profile?.mask,
            gateway: profile?.gateway, mac: profile?.registeredMAC)
    }

    private var networkStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 先让用户/程序确定用哪块网卡，避免"明明登记了却被判不匹配"
            VStack(alignment: .leading, spacing: 6) {
                Text(model.interfaceMatchingSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 标题单独一行：英文标题很长，和 Picker 并排会把选中值挤成一个字
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.t("W34"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { model.config.interfaceLock ?? "" },
                        set: { model.selectInterface($0.isEmpty ? nil : $0) })) {
                        Text(Copy.t("W35")).tag("")
                        ForEach(model.interfaceCandidates) { candidate in
                            Text("\(candidate.name)  \(candidate.macForAuthentication ?? "—")").tag(candidate.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            // 分隔符由界面画出来：IP 四格、MAC 六格，填满自动跳下一格
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                LabeledAddressField(title: "IP", kind: .ipv4, text: $ip,
                                    hint: Copy.t("W36"),
                                    onSubmit: focusNextField)
                    .onChange(of: ip) { _, newValue in
                        autofillNeighbours(from: newValue)
                    }
                LabeledAddressField(title: Copy.t("W37"), kind: .ipv4, text: $mask,
                                    hint: Copy.t("W38"),
                                    onSubmit: focusNextField)
                LabeledAddressField(title: Copy.t("W39"), kind: .ipv4, text: $gateway,
                                    hint: Copy.t("W40"),
                                    onSubmit: focusNextField)
                GridRow {
                    Text("DNS").frame(width: 72, alignment: .leading).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        AddressField(kind: .ipv4, text: Binding(
                            get: { FieldFormatting.ipv4ListInput(dns).components(separatedBy: ", ").first ?? "" },
                            set: { dns = FieldFormatting.ipv4ListInput($0) }))
                    }
                }
                LabeledAddressField(title: Copy.t("W41"), kind: .mac, text: $mac,
                                    hint: Copy.t("W42"),
                                    onSubmit: finish)
            }

            Label(Copy.t("W43"),
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SelfServiceHintRow(text: Copy.t("W44"))

            VStack(alignment: .leading, spacing: 6) {
                Button(Copy.t("W45")) { fillFromSystem() }
                    .buttonStyle(.borderedProminent)
                HStack(spacing: 8) {
                    if hasSavedProfile {
                        Button(Copy.t("W46")) { loadSavedProfile() }
                            .buttonStyle(.bordered)
                    }
                    Button(Copy.t("W47")) { clearFields() }
                        .buttonStyle(.bordered)
                }
            }
            if let note = suggestionNote {
                Text(note).font(.caption2).foregroundStyle(isSuggestionTrustworthy ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(model.orderedInterfaces.filter { $0.ipv4 != nil }, id: \.name) { item in
                Text("\(item.name)：\(item.ipv4 ?? "-")  \(item.mac ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .credentials {
                Button(Copy.t("W48")) { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(isLastStep ? Copy.t("W49") : Copy.t("W50")) { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var isLastStep: Bool {
        step == .network || (step == .link && !needsNetworkStep)
    }

    // MARK: 逻辑

    /// 打开向导时**不自动回填网络参数**（那些是敏感信息，清掉就该真的没了）。
    /// 只带出账号名与链接方式；要复用旧参数需用户主动点「载入上次保存的参数」。
    private func load() {
        let current = model.config
        account = current.account
        // 不把保存的密码静默填进输入框：用户看不出那是"旧的"，会以为是自己刚输的。
        // 有保存的密码时给一个明确选择（用已保存 / 重新输入）。
        let stored = current.account.isEmpty ? nil : CredentialStore.password(for: current.account)
        hasSavedPassword = (stored?.isEmpty == false)
        savedPasswordVerified = CredentialStore.verifiedAt(account: current.account) != nil
        password = model.password
        link = current.link
        hasSavedProfile = current.currentProfile.map {
            !(($0.ip ?? "").isEmpty || ($0.mask ?? "").isEmpty)
        } ?? false
    }

    /// 用户主动要求时才把已保存的参数填进来。
    private func loadSavedProfile() {
        guard let profile = model.config.currentProfile else { return }
        ip = profile.ip ?? ""
        mask = profile.mask ?? ""
        gateway = profile.gateway ?? ""
        dns = profile.dns.joined(separator: ", ")
        mac = profile.registeredMAC ?? ""
    }

    /// 只有当系统这块网卡是"手动配置"时，读数才可信（DHCP 的绝不能抄）。
    private func fillFromSystem() {
        model.refreshDiagnostics()          // 先拿到最新网卡列表，否则 MAC 可能为空
        let suggestion = model.parameterSuggestionForCurrentInterface()
        suggestionNote = suggestion.reason
        isSuggestionTrustworthy = suggestion.isTrustworthy
        // MAC 与 IP 是否 DHCP 无关：这块网卡的出厂 MAC 就是学校登记的那个，永远可以填
        if mac.isEmpty, let hardware = model.hardwareMACForCurrentInterface() {
            mac = hardware
        }
        guard suggestion.hasUsableValues else { return }
        ip = suggestion.ip ?? ""
        mask = suggestion.mask ?? ""
        gateway = suggestion.gateway ?? Self.gatewayGuess(from: ip) ?? ""
        dns = suggestion.dns.joined(separator: ", ")
        // 登记 MAC 用**出厂 MAC**（系统可能套了私有地址，直接抄当前值会认证失败）
        mac = model.config.interfaceLock
            .flatMap { name in model.interfaceCandidates.first { $0.name == name } }?
            .macForAuthentication
            ?? model.interfaceCandidates.first(where: { $0.ipv4 != nil })?.macForAuthentication
            ?? suggestion.mac ?? ""
    }

    /// IP 填完后：掩码空着就补 255.255.255.0；网关空着就按同网段补 .254
    private func autofillNeighbours(from address: String) {
        let parts = address.split(separator: "·").map(String.init)
        guard parts.count == 4 else { return }
        if mask.isEmpty { mask = "255·255·255·0" }
        if gateway.isEmpty {
            gateway = "\(parts[0])·\(parts[1])·\(parts[2])·254"
            suggestionNote = Copy.f("W51", gateway)
        }
    }

    /// 同网段网关的常见值：x.x.x.254（仅用于预填，可改）
    static func gatewayGuess(from address: String) -> String? {
        let parts = address.split(separator: "·").map(String.init)
        guard parts.count == 4 else { return nil }
        return "\(parts[0])·\(parts[1])·\(parts[2])·254"
    }

    /// Enter：把焦点交给下一个可输入的控件（macOS 的 key view 链）
    private func focusNextField() {
        NSApp.keyWindow?.selectNextKeyView(nil)
    }

    private func clearFields() {
        ip = ""; mask = ""; gateway = ""; dns = ""; mac = ""
    }

    private func advance() {
        errorText = nil
        switch step {
        case .credentials:
            let normalized = AccountFormat.normalize(account)
            guard !normalized.isEmpty else {
                errorText = Copy.f("W52", AccountFormat.mailDomain)
                return
            }
            if AccountFormat.analyze(normalized).kind == .unrecognized {
                errorText = AccountFormat.analyze(normalized).hint
                return
            }
            account = normalized
            if model.requirePasswordReentry, passwordConfirm != password {
                errorText = Copy.t("W53")
                return
            }
            guard !password.isEmpty else {
                errorText = hasSavedPassword
                    ? Copy.t("W54")
                    : Copy.t("W55")
                return
            }
            // 换账号时载入该账号已经存过的地址，别让用户重填
            loadProfileIfAny(for: account)
            step = .link
        case .link:
            if needsNetworkStep {
                step = .network
                Task { @MainActor in fillFromSystem() }   // 手动配置时自动填；DHCP 只提示原因
            } else {
                finish()
            }
        case .network:
            finish()
        }
    }

    private func goBack() {
        errorText = nil
        switch step {
        case .network: step = .link
        case .link: step = .credentials
        case .credentials: break
        }
    }

    private func loadProfileIfAny(for account: String) {
        guard let profile = model.config.accounts[account] else { return }
        ip = profile.ip ?? ""
        mask = profile.mask ?? ""
        gateway = profile.gateway ?? ""
        dns = profile.dns.joined(separator: ", ")
        mac = profile.registeredMAC ?? ""
    }

    private func finish() {
        errorText = nil

        if needsNetworkStep {
            let issues = NetworkValidation.issues(
                ip: ip.isEmpty ? nil : ip,
                mask: mask.isEmpty ? nil : mask,
                gateway: gateway.isEmpty ? nil : gateway,
                mac: mac.isEmpty ? nil : mac)
            if let first = issues.first {
                errorText = first.message
                return
            }
            if ip.isEmpty || mask.isEmpty || gateway.isEmpty || mac.isEmpty {
                errorText = Copy.t("W56")
                return
            }
        }

        let trimmedAccount = account.trimmingCharacters(in: .whitespaces)
        let capturedLink = link
        let capturedPassword = password
        // 界面用中间点显示，落盘统一成标准点分十进制
        let capturedIP = ip.isEmpty ? nil : NetworkValidation.canonical(ip)
        let capturedMask = mask.isEmpty ? nil : NetworkValidation.canonical(mask)
        let capturedGateway = gateway.isEmpty ? nil : NetworkValidation.canonical(gateway)
        let capturedDNS = dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let capturedMAC = mac.isEmpty ? nil : NetworkValidation.canonicalMAC(mac)
        let previousHint = model.config.accounts[trimmedAccount]?.interfaceHint
        let previousConfiguredAt = model.config.accounts[trimmedAccount]?.configuredAt

        // 关键：不要在按钮动作里同步拆掉自己的视图再开新窗口、启动引擎（AppKit 重入会崩）。
        // 先把数据落盘，回到主线程下一轮再关窗口、开状态窗、连接。
        FileLogger.shared.log("wizard: 完成，链路=\(capturedLink)，账号=\(trimmedAccount.isEmpty ? "-" : trimmedAccount)")
        Task { @MainActor in
            var config = model.config
            config.account = trimmedAccount
            config.link = capturedLink
            config.accounts[trimmedAccount] = AppConfig.NetworkProfile(
                ip: capturedIP, mask: capturedMask, gateway: capturedGateway,
                dns: capturedDNS, registeredMAC: capturedMAC,
                interfaceHint: previousHint,
                configuredAt: previousConfiguredAt ?? ISO8601DateFormatter().string(from: .now))
            model.config = config
            model.password = capturedPassword
            model.persist()
            try? CredentialStore.save(password: capturedPassword, account: trimmedAccount)

            model.finishWizard()
            // 让向导先真正退场，再创建结果窗口
            try? await Task.sleep(for: .milliseconds(200))
            model.presentConnectionStatus()
            model.connect()
        }
    }
}