import AppKit
import WebKit
import JLUGateCore
import JLUGateNet

/// `JLU.WIFI` 的网页认证：**在菜单栏面板里**渲染登录页。
///
/// 历史：原来自建 NSWindow（`PortalWindow`）承载 WKWebView，真机上会在 AppKit
/// 布局/显示周期抛 ObjC 异常导致 SIGABRT；现在统一走面板，不再创建窗口。
///
/// 设计取舍（决策 D-001）不变：不做表单重放、不做 DOM 操作/自动填充。
final class WKPortalBrowser: PortalBrowser, @unchecked Sendable {
    private weak var model: AppModel?

    @MainActor
    init(model: AppModel) {
        self.model = model
    }

    func presentLogin(url: URL) async -> PortalLoginResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<PortalLoginResult, Never>) in
            Task { @MainActor in
                guard let model else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                model.presentPortalLogin(url, continuation: continuation)
            }
        }
    }

    func clearCookies() async {
        await MainActor.run {
            let store = WKWebsiteDataStore.default()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) {}
        }
    }
}
