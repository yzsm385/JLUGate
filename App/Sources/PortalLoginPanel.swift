import SwiftUI
import WebKit
import JLUGateCore
import JLUGateNet

/// 网页认证面板：把 `JLU.WIFI` 的登录页直接放进菜单栏面板里渲染。
///
/// 为什么不再单开窗口：真机崩溃栈是 AppKit 在 display cycle 抛 ObjC 异常，
/// 触发点就是"自建 NSWindow 承载 SwiftUI/WebKit"。面板是已验证可用的路径。
struct PortalLoginPanel: View {
    @Environment(AppModel.self) private var model
    let url: URL

    var body: some View {
        VStack(spacing: 8) {
            Text("请在下方完成校园网登录。程序不会保存或上传你的明文密码。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PanelWebView(url: url)
                .frame(height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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

private struct PanelWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 默认数据仓：Cookie 落盘，下次仍可静默（PLAN §5.4.2）
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url != url { view.load(URLRequest(url: url)) }
    }
}
