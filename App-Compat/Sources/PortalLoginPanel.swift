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
            Text("请在下方完成校园网登录。程序不会保存或上传你的明文密码。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !trusted { warning }

            VStack(spacing: 10) {
                Image(systemName: trusted ? "safari" : "exclamationmark.shield")
                    .font(.system(size: 34))
                    .foregroundStyle(trusted ? Color.secondary : Color.orange)
                Text(trusted ? "已用默认浏览器打开登录页" : "没有自动打开：地址不在 jlu.edu.cn 下")
                    .font(.callout)
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(trusted
                     ? "在浏览器里完成登录后，回到这里点「已完成登录」。程序不会接触你的明文密码。"
                     : "确认当前 Wi-Fi 是学校的 JLU.WIFI / JLU.PC，并且这个地址可信，再继续。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(trusted ? "重新打开登录页" : "仍要打开这个页面") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, trusted ? 40 : 20)

            HStack(spacing: 8) {
                Button("取消") { model.finishPortalLogin(.cancelled) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("已完成登录") { model.finishPortalLogin(.succeeded) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("这个登录页不是 jlu.edu.cn 的地址", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).bold()
                .foregroundStyle(.orange)
            Text("只有在确认当前 Wi-Fi 是学校的 JLU.WIFI / JLU.PC 时才继续；"
                 + "名字可疑的网络里别在这里输入账号密码。")
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
