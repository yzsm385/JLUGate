import AppKit
import WebKit
import JLUGateCore
import JLUGateNet

/// `JLU.WIFI` 的网页认证窗口：`WKWebView` + 持久化 Cookie（PLAN §5.4.2）。
///
/// 设计取舍（决策 D-001）：
/// - 认证**就是浏览器**，不做表单重放、**不做任何 DOM 操作/自动填充**；
///   页面改版、JS 加密、验证码全都天然免疫，程序也从不接触明文密码；
/// - 登录成功靠两条信号：URL 离开门户域，或用户点"已完成"；真正的判定仍由引擎的 204 探针做。
final class WKPortalBrowser: PortalBrowser, @unchecked Sendable {
    func presentLogin(url: URL) async -> PortalLoginResult {
        await PortalWindow.present(url: url)
    }

    func clearCookies() async {
        await MainActor.run {
            let store = WKWebsiteDataStore.default()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) {}
        }
    }
}

@MainActor
final class PortalWindow: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static func present(url: URL) async -> PortalLoginResult {
        let window = PortalWindow(url: url)
        return await window.run()
    }

    private let window: NSWindow
    private let webView: WKWebView
    private let entryHost: String?
    private var continuation: CheckedContinuation<PortalLoginResult, Never>?

    private init(url: URL) {
        entryHost = url.host

        let configuration = WKWebViewConfiguration()
        // 用默认数据仓才能让 Cookie 落盘、下次仍可静默（PLAN §5.4.2）
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 520),
                           configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = "JLU Gate · 网页认证"
        window.center()
        window.delegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        window.contentView = makeContentView()
    }

    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 580))

        let hint = NSTextField(labelWithString: "请在下方完成校园网登录。程序不会保存或上传你的明文密码。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "已完成登录", target: self, action: #selector(handleDone))
        doneButton.bezelStyle = .rounded
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(handleCancel))
        cancelButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [cancelButton, doneButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(hint)
        container.addSubview(webView)
        container.addSubview(buttons)

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            webView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            webView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        return container
    }

    private func run() async -> PortalLoginResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish(_ result: PortalLoginResult) {
        guard let continuation else { return }
        self.continuation = nil
        window.orderOut(nil)
        window.delegate = nil
        continuation.resume(returning: result)
    }

    @objc private func handleDone() { finish(.succeeded) }
    @objc private func handleCancel() { finish(.cancelled) }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        finish(.cancelled)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        FileLogger.shared.log("portal window load: \(webView.url?.absoluteString ?? "-")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        FileLogger.shared.log("portal window loaded: \(webView.url?.absoluteString ?? "-")")
        // URL 离开门户域 → 基本可以认为登录完成；最终仍由引擎的 204 探针确认
        if let host = webView.url?.host, let entryHost, host != entryHost {
            finish(.succeeded)
        }
    }
}
