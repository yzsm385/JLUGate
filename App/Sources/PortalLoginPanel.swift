import SwiftUI
import JLUGateCore
import JLUGateNet

/// 网页认证面板：登录页交给**系统浏览器**，面板里只做"已完成 / 取消"确认。
///
/// 不再内嵌 WKWebView：真机崩溃栈显示 AppKit 在 display cycle 抛 ObjC 异常，
/// 而 WebKit 在菜单栏面板/自建窗口里渲染是已知诱因；页面交互交给浏览器零风险。
struct PortalLoginPanel: View {
    @Environment(AppModel.self) private var model
    let url: URL

    var body: some View {
        VStack(spacing: 8) {
            Text("请在下方完成校园网登录。程序不会保存或上传你的明文密码。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Image(systemName: "safari")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("已用默认浏览器打开登录页").font(.callout)
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("在浏览器里完成登录后，回到这里点「已完成登录」。程序不会接触你的明文密码。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重新打开登录页") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)

            HStack(spacing: 8) {
                Button("取消") { model.finishPortalLogin(.cancelled) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("已完成登录") { model.finishPortalLogin(.succeeded) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
