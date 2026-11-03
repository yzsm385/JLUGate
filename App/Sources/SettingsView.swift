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
        var autoDetect = true
        var autoConnect = true
        var portalEntry = ""
        var helperAuthorized = false
    }

    var body: some View {
        Form {
            Section("账号") {
                TextField("学校邮箱前缀（如 zhangcyy2122 / zhangshanwu）", text: $draft.account)
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
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    LabeledAddressField(title: "IP", kind: .ipv4, text: $draft.ip)
                    LabeledAddressField(title: "子网掩码", kind: .ipv4, text: $draft.mask)
                    LabeledAddressField(title: "网关", kind: .ipv4, text: $draft.gateway)
                    LabeledAddressField(title: "DNS", kind: .ipv4, text: Binding(
                        get: { draft.dns.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "" },
                        set: { draft.dns = $0 }))
                    LabeledAddressField(title: "登记 MAC", kind: .mac, text: $draft.registeredMAC)
                }
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
                            .buttonStyle(.glassProminent)
                        if saved {
                            Label("已保存", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("关闭") { model.closeSettings() }
                            .buttonStyle(.glass)
                    }
                    HStack(spacing: 8) {
                        Button("重新检测") { model.refreshDiagnostics() }
                        Button("从剪贴板导入参数卡") {
                            if model.importConfigCardFromClipboard() {
                                load()
                                saved = true
                            }
                        }
                        Spacer()
                        Button("清空网络参数") {
                            draft.ip = ""; draft.mask = ""; draft.gateway = ""
                            draft.dns = ""; draft.registeredMAC = ""
                            model.clearNetworkParameters()
                            saved = true
                        }
                        Button("删除已保存的密码") {
                            model.clearSavedPassword()
                            draft.password = ""
                            saved = true
                        }
                        Button("重置本机配置…") { model.resetLocalConfiguration() }
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .onAppear { load() }
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
        draft.autoDetect = config.autoDetect
        draft.autoConnect = config.autoConnect
        draft.portalEntry = config.portal.entryURL ?? ""
        draft.helperAuthorized = config.routeGuard.helperAuthorized == true
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

        let profile = AppConfig.NetworkProfile(
            ip: draft.ip.isEmpty ? nil : draft.ip,
            mask: draft.mask.isEmpty ? nil : draft.mask,
            gateway: draft.gateway.isEmpty ? nil : draft.gateway,
            dns: draft.dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            registeredMAC: draft.registeredMAC.isEmpty ? nil : draft.registeredMAC,
            interfaceHint: config.accounts[draft.account]?.interfaceHint,
            configuredAt: config.accounts[draft.account]?.configuredAt
                ?? ISO8601DateFormatter().string(from: .now))
        config.accounts[draft.account] = profile

        model.config = config
        model.password = draft.password
        model.persist()
        if !hadProfileForAccount, config.link != "jluWiFi" {
            // 新账号没有档案：走一次向导把地址填全，别让用户猜为什么认证失败
            model.presentWizard()
        }
        if !draft.password.isEmpty, !DevOverrides.isEnabled {
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
