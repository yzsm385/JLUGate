import Foundation

/// 仅供本地调试：`swift run` 时手动调一次，验证静默登录接口是否通。
/// 生产路径由 `PortalEngine.presentLogin` 调用 `EportalClient`。
public enum EportalClientProbe {
    public static func run(entry: String, account: String, password: String) async {
        let client = EportalClient()
        guard let url = URL(string: entry) else { return }
        let base = await client.resolveEportalBase(entry: url)
        print("入口: \(entry)")
        print("解析到的 EPortal 根: \(base?.absoluteString ?? "nil")")
        let outcome = await client.login(entry: url, account: account, password: password,
                                         clientIP: nil, clientMAC: nil)
        print("登录结果: \(outcome)")
    }
}
