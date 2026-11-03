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

    var body: some View {
        @Namespace var glassNamespace

        VStack(alignment: .leading, spacing: 16) {
            header

            GlassEffectContainer(spacing: 14) {
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
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .glassEffectID("wizard-card", in: glassNamespace)
            }

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
        .onAppear(perform: load)
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

            TextField("学号 / 账号", text: $account)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)

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
            Picker("接入方式", selection: $link) {
                Text("自动识别（推荐）").tag("auto")
                Text("有线").tag("wired")
                Text("JLU.PC（无线 · Dr.Com）").tag("jluPC")
                Text("JLU.WIFI（网页认证）").tag("jluWiFi")
            }
            .pickerStyle(.radioGroup)

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

    private var hintForLink: String {
        switch link {
        case "wired": "有线需要学校分配的固定 IP / 掩码 / 网关 / 登记 MAC；下一步会让你填。"
        case "jluPC": "JLU.PC 与有线共用同一组静态地址；没填过的话下一步会让你填。"
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
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("IP").frame(width: 72, alignment: .leading)
                    TextField("学校分配的固定 IP", text: $ip)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("子网掩码").frame(width: 72, alignment: .leading)
                    TextField("通常是 255.255.255.0", text: $mask)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("网关").frame(width: 72, alignment: .leading)
                    TextField("与 IP 同网段", text: $gateway)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("DNS").frame(width: 72, alignment: .leading)
                    TextField("可留空", text: $dns)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("登记 MAC").frame(width: 72, alignment: .leading)
                    TextField("该网卡的 MAC", text: $mac)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Label("这些值只能从学校通知单照抄。下面是系统当前读数，仅供核对——**不要照抄 DHCP 分到的地址**。",
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                    .buttonStyle(.glass)
            }
            Spacer()
            Button(isLastStep ? "完成" : "下一步") { advance() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var isLastStep: Bool {
        step == .network || (step == .link && !needsNetworkStep)
    }

    // MARK: 逻辑

    private func load() {
        let current = model.config
        account = current.account
        password = model.password
        link = current.link
        if let profile = current.currentProfile {
            ip = profile.ip ?? ""
            mask = profile.mask ?? ""
            gateway = profile.gateway ?? ""
            dns = profile.dns.joined(separator: ", ")
            mac = profile.registeredMAC ?? ""
        }
    }

    private func advance() {
        errorText = nil
        switch step {
        case .credentials:
            guard !account.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorText = "请填写学号 / 账号"
                return
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
        var config = model.config
        config.account = trimmedAccount
        config.link = link
        // 账号密码三网共用：只存一份，存在账号名下
        config.accounts[trimmedAccount] = AppConfig.NetworkProfile(
            ip: ip.isEmpty ? nil : ip,
            mask: mask.isEmpty ? nil : mask,
            gateway: gateway.isEmpty ? nil : gateway,
            dns: dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            registeredMAC: mac.isEmpty ? nil : mac,
            interfaceHint: config.accounts[trimmedAccount]?.interfaceHint,
            configuredAt: config.accounts[trimmedAccount]?.configuredAt
                ?? ISO8601DateFormatter().string(from: .now))
        model.config = config
        model.password = password
        model.persist()
        try? CredentialStore.save(password: password, account: trimmedAccount)
        model.finishWizard()
        model.connect()
    }
}
