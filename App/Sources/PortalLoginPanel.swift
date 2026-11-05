import SwiftUI
import JLUGateCore
import JLUGateNet

/// 网页认证面板：登录页交给**系统浏览器**，面板里只做"已完成 / 取消"确认。
///
/// 不再内嵌 WKWebView：真机崩溃栈显示 AppKit 在 display cycle 抛 ObjC 异常，
/// 而 WebKit 在菜单栏面板/自建窗口里渲染是已知诱因；页面交互交给浏览器零风险。
///
/// 入口地址不是 `*.jlu.edu.cn` 时不会自动打开浏览器，这里会写明原因：
/// 有人开个热点把门户指向自己的站点，用户一输账号就中招——至少让他先看一眼地址。
struct PortalLoginPanel: View {
    @Environment(AppModel.self) private var model
    let url: URL

    private var trusted: Bool { PortalTrust.isTrusted(url) }

    var body: some View {
        VStack(spacing: 8) {
            Text(Copy.t("A01"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !trusted { warning }

            VStack(spacing: 10) {
                Image(systemName: trusted ? "safari" : "exclamationmark.shield")
                    .font(.system(size: 34))
                    .foregroundStyle(trusted ? Color.secondary : Color.orange)
                Text(trusted ? Copy.t("A02") : Copy.t("A03"))
                    .font(.callout)
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(trusted
                     ? Copy.t("A04")
                     : Copy.t("A05"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(trusted ? Copy.t("A06") : Copy.t("A07")) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, trusted ? 40 : 20)

            HStack(spacing: 8) {
                Button(Copy.t("A08")) { model.finishPortalLogin(.cancelled) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(Copy.t("A09")) { model.finishPortalLogin(.succeeded) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(Copy.t("A10"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).bold()
                .foregroundStyle(.orange)
            Text(Copy.t("A11")
                 + Copy.t("A12"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
