import SwiftUI
import JLUGateCore

/// 「校园网门户」：只用系统浏览器打开，不在 App 内嵌 WebKit。
///
/// 原因（真机崩溃）：菜单栏面板/自建窗口里渲染 WKWebView 会在 AppKit 的
/// display cycle 抛 ObjC 异常（crash.txt / .ips 已证实）。门户页只是展示性内容，
/// 交给系统浏览器零风险；页面 HTML 仍会缓存到本机供离线查看。
struct PortalViewerView: View {
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe.asia.australia")
                Text("校园网门户").font(.headline)
                Spacer()
            }

            if let url {
                Text(url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("门户页（校园网欢迎/广告页）用系统浏览器打开。"
                     + "App 内不加载网页，避免渲染崩溃。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("在浏览器中打开", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("还没有拿到门户地址")
                    .font(.callout)
                Text("先连接一次校园网（或让程序被门户拦一次），这里会自动记下地址。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text(PortalAssets.systemPopupNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(PortalAssets.disableCaptiveAssistantCommand,
                                               forType: .string)
            } label: {
                Label("复制关闭系统弹窗的命令", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
