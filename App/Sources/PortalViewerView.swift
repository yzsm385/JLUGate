import SwiftUI
import WebKit
import JLUGateCore

/// App 内的「校园网门户」：把那个欢迎/广告页收进来，**只在用户点开时**加载。
/// 不用系统那个自动弹窗，也不会自己跳出来。
struct PortalViewerView: View {
    let url: URL?
    @State private var cachedAt: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe.asia.australia")
                VStack(alignment: .leading, spacing: 1) {
                    Text("校园网门户").font(.headline)
                    Text(url?.absoluteString ?? "还没有缓存的门户地址")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("复制关闭系统弹窗的命令") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(PortalAssets.disableCaptiveAssistantCommand, forType: .string)
                }
                .buttonStyle(.glass)
                .help(PortalAssets.disableCaptiveAssistantCommand)
            }
            .padding(12)

            Divider()

            if let url {
                WebView(url: url)
                    .frame(minWidth: 640, minHeight: 480)
            } else {
                VStack(spacing: 8) {
                    Text("还没有拿到门户地址").font(.headline)
                    Text("先连接一次校园网（或让程序被门户拦一次），这里会自动缓存。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            Text(PortalAssets.systemPopupNote)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 760, height: 620)
    }
}

private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // 与登录窗共用 Cookie，才能看到已登录后的页面
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url != url { view.load(URLRequest(url: url)) }
    }
}
