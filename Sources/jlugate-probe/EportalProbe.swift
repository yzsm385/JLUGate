import Foundation
import JLUGateNet

enum EportalProbeCLI {
    static func run(entry: String, account: String, password: String) async -> Int32 {
        let client = EportalClient()
        guard let url = URL(string: entry) else { print("入口不合法"); return 2 }
        print("入口：\(entry)")
        let base = await client.resolveEportalBase(entry: url)
        print("EPortal 根：\(base?.absoluteString ?? "nil")")
        let outcome = await client.login(entry: url, account: account, password: password,
                                         clientIP: nil, clientMAC: nil)
        print("结果：\(outcome)")
        switch outcome {
        case .success: print("✅ 静默登录成功（还需 204 确认）")
        case .kicked(let m): print("⚠️ 被挤下线：\(m)")
        case .failed(let m): print("❌ 失败：\(m)")
        case .unsupported: print("ℹ️ 这个门户不支持静默登录")
        }
        return 0
    }
}
