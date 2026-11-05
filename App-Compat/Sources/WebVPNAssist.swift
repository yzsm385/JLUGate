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
                Text(Copy.t("A13")).font(.caption).bold()
                Spacer()
                Button(Copy.t("A14")) { model.runInspection() }
                    .buttonStyle(.link).font(.system(size: 10))
            }
            Text(Copy.t("A15"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button {
                    openVPN()
                } label: {
                    Label(Copy.t("A16"), systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)

                Button(Copy.t("A17")) { copyPassword() }
                    .buttonStyle(.bordered).controlSize(.small)
            }

            Text(Copy.t("A18"))
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
            hint = Copy.f("A19", Redact.account(model.account))
        } else {
            hint = Copy.t("A20")
        }
    }

    private func copyPassword() {
        guard let password = model.storedPasswordForPrefill(), !password.isEmpty else {
            hint = Copy.t("A21")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        let changeCount = pasteboard.changeCount
        hint = Copy.t("A22")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
