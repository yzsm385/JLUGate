import SwiftUI
import JLUGateCore
import JLUGateNet

/// 首次启动向导（PLAN §9.1）。
///
/// 核心是第 3 步：静态参数只能人工照抄，系统里的 DHCP 值一律不能抄。
/// 向导只在"首次使用"或"换账号"时出现，之后设置页里只读展示。
struct WizardView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var link = "auto"
    @State private var account = ""
    @State private var password = ""
    @State private var ip = ""
    @State private var mask = ""
    @State private var gateway = ""
    @State private var dns = ""
    @State private var mac = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Group {
                switch step {
                case 0: linkStep
                case 1: accountStep
                default: networkStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
            footer
        }
        .padding(22)
        .frame(width: 520, height: 460)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("欢迎使用 JLU Gate")
                .font(.title2.bold())
            Text("第 \(step + 1) / 3 步 · \(stepTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: "选择接入方式"
        case 1: "账号与密码"
        default: "网络参数（只能人工照抄）"
        }
    }

    // MARK: 步骤

    private var linkStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("接入方式", selection: $link) {
                Text("自动（推荐）").tag("auto")
                Text("有线").tag("wired")
                Text("JLU.PC（无线）").tag("jluPC")
                Text("JLU.WIFI（网页认证）").tag("jluWiFi")
            }
            .pickerStyle(.radioGroup)

            Text("自动模式会先发 1 个认证探测包判断是不是校园网；不是校园网就不发任何认证。可以在设置里关掉。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("当前识别到的接口：\(model.interfaces.map(\.name).joined(separator: "、"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("学号 / 账号", text: $account)
                .textFieldStyle(.roundedBorder)
            SecureField("密码（存 Keychain）", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("密码只用于本地算认证摘要（有线）或自动填充登录页（JLU.WIFI），不会上传到任何第三方。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var networkStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("IP").frame(width: 70, alignment: .leading)
                    TextField("192.0.2.10", text: $ip).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("子网掩码").frame(width: 70, alignment: .leading)
                    TextField("255.255.255.0", text: $mask).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("网关").frame(width: 70, alignment: .leading)
                    TextField("192.0.2.1", text: $gateway).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("DNS").frame(width: 70, alignment: .leading)
                    TextField("10.10.10.10, 10.10.10.10", text: $dns).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("登记 MAC").frame(width: 70, alignment: .leading)
                    TextField("aa:bb:cc:dd:ee:ff", text: $mac).textFieldStyle(.roundedBorder)
                }
            }

            Text("这些值是学校按宿舍端口分配的固定值，必须从通知单人工照抄。下面灰字是系统当前值，**仅供核对**：")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.interfaces.filter { $0.ipv4 != nil }, id: \.name) { item in
                Text("\(item.name)：\(item.ipv4 ?? "-")  \(item.mac ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text("不要在 DHCP 模式下直接照抄系统地址——那一定是错的。")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("上一步") { step -= 1 }
            }
            Spacer()
            if step < 2 {
                Button("下一步") { advance() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("完成") { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: 逻辑

    private func load() {
        let current = model.config
        link = current.link
        account = current.account
        password = model.password
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
        case 0:
            step = 1
        case 1:
            guard !account.isEmpty, !password.isEmpty else {
                errorText = "账号和密码都得填"
                return
            }
            step = 2
        default:
            break
        }
    }

    private func finish() {
        errorText = nil
        // 实时校验：能当场发现的错误不要留到认证时
        if !ip.isEmpty, IPv4Address(ip) == nil { errorText = "IP 不是合法的 IPv4"; return }
        if !gateway.isEmpty, IPv4Address(gateway) == nil { errorText = "网关不是合法的 IPv4"; return }
        if !mac.isEmpty, MACAddress(mac) == nil { errorText = "MAC 格式不对（aa:bb:cc:dd:ee:ff）"; return }
        if link != "jluWiFi", ip.isEmpty {
            errorText = "有线 / JLU.PC 需要填写 IP"
            return
        }

        var config = model.config
        config.link = link
        config.account = account
        config.accounts[account] = AppConfig.NetworkProfile(
            ip: ip.isEmpty ? nil : ip,
            mask: mask.isEmpty ? nil : mask,
            gateway: gateway.isEmpty ? nil : gateway,
            dns: dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            registeredMAC: mac.isEmpty ? nil : mac,
            interfaceHint: config.currentProfile?.interfaceHint,
            configuredAt: ISO8601DateFormatter().string(from: .now))
        model.config = config
        model.password = password
        model.persist()
        try? CredentialStore.save(password: password, account: account)
        model.finishWizard()
    }
}
