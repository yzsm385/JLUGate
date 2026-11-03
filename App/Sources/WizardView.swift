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
    @State private var link = "auto"
    @State private var ip = ""
    @State private var mask = ""
    @State private var gateway = ""
    @State private var dns = ""
    @State private var mac = ""
    @State private var errorText: String?
    @State private var hasSavedProfile = false
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
            .jluGlassCard(cornerRadius: 18)

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
        .frame(width: 540, height: 480)
        .onAppear {
            Task { @MainActor in
                load()
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
            Text("欢迎使用 JLU Gate")
                .font(.title2.bold())
            Text("第 \(step.rawValue + 1) / \(Step.allCases.count) 步 · \(stepTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepTitle: String {
        switch step {
        case .credentials: "账号与密码（三网共用）"
        case .link: "选择接入方式"
        case .network: "网络参数"
        }
    }

    // MARK: 步骤：账号密码

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("账号密码只填一次，有线 / JLU.PC / JLU.WIFI 三个入口共用。",
                  systemImage: "person.badge.key")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("学校邮箱前缀（不是整个邮箱）", text: $account)
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

            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)

            Label(keychainNote, systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var keychainNote: String {
        switch CredentialStore.backend {
        case .keychain: "密码保存在系统钥匙串，只用于本地计算认证摘要 / 自动登录。"
        case .file: "当前是本机构建版（无开发者签名），密码保存在仅本用户可读的本地文件里。"
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

            if !model.interfaces.isEmpty {
                Text("当前可用：\(model.interfaces.filter(\.isUsableForAuthentication).map(\.name).joined(separator: "、"))")
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
        LinkOption(value: "auto", title: "自动识别（推荐）", detail: "先探一次网络，判断走 Dr.Com 还是网页认证"),
        LinkOption(value: "wired", title: "有线", detail: "需要学校分配的固定 IP / 掩码 / 网关 / 登记 MAC"),
        LinkOption(value: "jluPC", title: "JLU.PC（无线 · Dr.Com）", detail: "用本机 Wi-Fi 网卡 MAC 认证"),
        LinkOption(value: "jluWiFi", title: "JLU.WIFI（网页认证）", detail: "不需要静态地址，浏览器里登录一次"),
    ]

    private var hintForLink: String {
        switch link {
        case "wired": "有线需要学校分配的固定 IP / 掩码 / 网关 / 登记 MAC；下一步会让你填。"
        case "jluPC": JLUAccessPolicy.jluPCHint
        case "jluWiFi": "网页认证不需要静态地址，登录时用浏览器输入同一套账号密码即可。"
        default: "自动模式会先探一次网络，判断该走 Dr.Com 还是网页认证；不是校园网就不发任何认证。"
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
                Picker("使用哪块网卡", selection: Binding(
                    get: { model.config.interfaceLock ?? "" },
                    set: { model.selectInterface($0.isEmpty ? nil : $0) })) {
                    Text("自动（按 MAC 认）").tag("")
                    ForEach(model.interfaceCandidates) { candidate in
                        Text("\(candidate.name)  \(candidate.macForAuthentication ?? "—")").tag(candidate.name)
                    }
                }
                .frame(maxWidth: 360)
            }

            // 分隔符由界面画出来：IP 四格、MAC 六格，填满自动跳下一格
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                LabeledAddressField(title: "IP", kind: .ipv4, text: $ip)
                LabeledAddressField(title: "子网掩码", kind: .ipv4, text: $mask)
                LabeledAddressField(title: "网关", kind: .ipv4, text: $gateway)
                GridRow {
                    Text("DNS").frame(width: 72, alignment: .leading).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        AddressField(kind: .ipv4, text: Binding(
                            get: { FieldFormatting.ipv4ListInput(dns).components(separatedBy: ", ").first ?? "" },
                            set: { dns = FieldFormatting.ipv4ListInput($0) }))
                    }
                }
                LabeledAddressField(title: "登记 MAC", kind: .mac, text: $mac)
            }

            Label("这些值只能从学校通知单照抄。下面是系统当前读数，仅供核对——**不要照抄 DHCP 分到的地址**。",
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("用系统当前读数填入") { fillFromSystem() }
                    .buttonStyle(.borderedProminent)
                if hasSavedProfile {
                    Button("载入上次保存的参数") { loadSavedProfile() }
                        .buttonStyle(.bordered)
                }
                Button("清空这几格") { clearFields() }
                    .buttonStyle(.bordered)
            }
            if let note = suggestionNote {
                Text(note).font(.caption2).foregroundStyle(isSuggestionTrustworthy ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(model.interfaces.filter { $0.ipv4 != nil }, id: \.name) { item in
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
                Button("上一步") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(isLastStep ? "完成" : "下一步") { advance() }
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
        // 已经保存过的密码直接带出来：用户输过一次就不该再输第二次
        password = model.password.isEmpty
            ? (CredentialStore.password(for: current.account) ?? "")
            : model.password
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
        let suggestion = model.parameterSuggestionForCurrentInterface()
        suggestionNote = suggestion.reason
        isSuggestionTrustworthy = suggestion.isTrustworthy
        guard suggestion.hasUsableValues else { return }
        ip = suggestion.ip ?? ""
        mask = suggestion.mask ?? ""
        gateway = suggestion.gateway ?? ""
        dns = suggestion.dns.joined(separator: ", ")
        // 登记 MAC 用**出厂 MAC**（系统可能套了私有地址，直接抄当前值会认证失败）
        mac = model.config.interfaceLock
            .flatMap { name in model.interfaceCandidates.first { $0.name == name } }?
            .macForAuthentication
            ?? model.interfaceCandidates.first(where: { $0.ipv4 != nil })?.macForAuthentication
            ?? suggestion.mac ?? ""
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
                errorText = "请填写账号（学校邮箱 @\(AccountFormat.mailDomain) 前面的那一段）"
                return
            }
            if AccountFormat.analyze(normalized).kind == .unrecognized {
                errorText = AccountFormat.analyze(normalized).hint
                return
            }
            account = normalized
            let stored = CredentialStore.password(for: account) ?? ""
            if password.isEmpty, !stored.isEmpty {
                password = stored          // 本机存过：直接复用，不逼用户再输
            }
            guard !password.isEmpty else {
                errorText = "请填写密码"
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
                errorText = "有线 / JLU.PC 需要填全 IP、掩码、网关与登记 MAC"
                return
            }
        }

        let trimmedAccount = account.trimmingCharacters(in: .whitespaces)
        let capturedLink = link
        let capturedPassword = password
        let capturedIP = ip.isEmpty ? nil : ip
        let capturedMask = mask.isEmpty ? nil : mask
        let capturedGateway = gateway.isEmpty ? nil : gateway
        let capturedDNS = dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let capturedMAC = mac.isEmpty ? nil : mac
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