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
        var channel = "nw"
        var server = "10.100.61.3"
        var serverPort = "61440"
        var localPort = "61440"
        var ip = ""
        var mask = ""
        var gateway = ""
        var dns = ""
        var registeredMAC = ""
        var launchAtLogin = true
    }

    var body: some View {
        Form {
            Section("账号") {
                TextField("学号 / 账号", text: $draft.account)
                SecureField("密码（存 Keychain）", text: $draft.password)
            }

            Section("链路") {
                Picker("接入方式", selection: $draft.link) {
                    Text("自动").tag("auto")
                    Text("有线").tag("wired")
                    Text("JLU.PC").tag("jluPC")
                    Text("JLU.WIFI").tag("jluWiFi")
                }
                Picker("通道实现", selection: $draft.channel) {
                    Text("NW（生产）").tag("nw")
                    Text("BSD（诊断/兜底）").tag("bsd")
                }
            }

            Section {
                TextField("IP", text: $draft.ip)
                TextField("子网掩码", text: $draft.mask)
                TextField("网关", text: $draft.gateway)
                TextField("DNS（逗号分隔）", text: $draft.dns)
                TextField("登记 MAC", text: $draft.registeredMAC)
            } header: {
                Text("静态网络参数")
            } footer: {
                Text("学校按宿舍端口分配固定地址，必须人工照抄；下面灰色的是系统当前值，仅供核对，**不要照抄 DHCP 分到的地址**。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("系统当前值（仅供核对）") {
                ForEach(model.interfaces, id: \.name) { item in
                    Text("\(item.name)：\(item.ipv4 ?? "无 IPv4")  \(item.mac ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("路由：\(model.routeSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("高级") {
                TextField("服务器", text: $draft.server)
                TextField("服务器端口", text: $draft.serverPort)
                TextField("本地端口（必须是 61440）", text: $draft.localPort)
                Toggle("开机自启", isOn: $draft.launchAtLogin)
            }

            Section {
                HStack {
                    Button("保存") { save() }
                        .buttonStyle(.glass)
                    Button("重新检测") { model.refreshDiagnostics() }
                    if saved {
                        Label("已保存", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .onAppear { load() }
    }

    private func load() {
        let config = model.config
        let profile = config.currentProfile
        draft.account = config.account
        draft.password = model.password
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
    }

    private func save() {
        var config = model.config
        config.account = draft.account
        config.link = draft.link
        config.channel = draft.channel
        config.server = draft.server
        config.serverPort = Int(draft.serverPort) ?? 61440
        config.localPort = Int(draft.localPort) ?? 61440
        config.launchAtLogin = draft.launchAtLogin

        let profile = AppConfig.NetworkProfile(
            ip: draft.ip.isEmpty ? nil : draft.ip,
            mask: draft.mask.isEmpty ? nil : draft.mask,
            gateway: draft.gateway.isEmpty ? nil : draft.gateway,
            dns: draft.dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            registeredMAC: draft.registeredMAC.isEmpty ? nil : draft.registeredMAC,
            interfaceHint: config.currentProfile?.interfaceHint,
            configuredAt: config.currentProfile?.configuredAt
                ?? ISO8601DateFormatter().string(from: .now))
        config.accounts[draft.account] = profile

        model.config = config
        model.password = draft.password
        model.persist()
        if !draft.password.isEmpty {
            try? CredentialStore.save(password: draft.password, account: draft.account)
        }
        LoginItem.apply(enabled: draft.launchAtLogin)
        model.refreshDiagnostics()
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            saved = false
        }
    }
}
