import SwiftUI
import AppKit
import JLUGateCore

/// 不在校园网时的"给出东西"，而不是只说一句"去连 WebVPN"：
/// 直接打开 WebVPN、把账号复制好、把步骤写在眼前，登完点一下重新检测。
struct WebVPNAssistCard: View {
    @Environment(AppModel.self) private var model

    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                Text("校园网认证没通").font(.caption).bold()
                Spacer()
                Button("重测") { model.runInspection() }
                    .buttonStyle(.link).font(.system(size: 10))
            }
            Text("如果确实在校外用热点/流量，校内系统要走 WebVPN；插着网线在校园网内则先重试认证。按钮会打开 WebVPN 并复制账号。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button {
                    openVPN()
                } label: {
                    Label("打开 WebVPN", systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)

                Button("复制密码") { copyPassword() }
                    .buttonStyle(.bordered).controlSize(.small)
            }

            Text("步骤：打开后在「师生普通登录」里选统一身份认证 → 粘贴账号（已复制）→ 输入密码 → 登录后回来点「重测」。")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint {
                Text(hint).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openVPN() {
        guard let url = URL(string: "https://vpn.jlu.edu.cn/") else { return }
        NSWorkspace.shared.open(url)
        if !model.account.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(model.account, forType: .string)
            hint = "账号已复制：\(Redact.account(model.account))"
        } else {
            hint = "还没保存账号——先在设置里填一次"
        }
    }

    private func copyPassword() {
        guard let password = model.storedPasswordForPrefill(), !password.isEmpty else {
            hint = "本机没有保存密码——先在设置里保存一次"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        let changeCount = pasteboard.changeCount
        hint = "密码已复制，60 秒后自动清空"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
