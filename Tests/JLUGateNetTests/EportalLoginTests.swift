import Testing
import Foundation
@testable import JLUGateNet

@Suite("网页认证：静默登录接口解析")
struct EportalLoginTests {
    @Test("EPortal 返回 result=1 视为成功")
    func success() {
        #expect(EportalClient.parse(#"dr1003({"result":1,"msg":"Portal协议认证成功"})"#) == .success)
    }

    @Test("账号已在别处在线 → 判定为被挤掉")
    func kicked() {
        let outcome = EportalClient.parse(#"dr1003({"result":0,"msg":"该账号已在线，请先下线"})"#)
        if case .kicked = outcome {} else { Issue.record("应判定为被挤掉，实际 \(outcome)") }
    }

    @Test("密码错 / 其他拒绝 → 失败并带原因")
    func failed() {
        let outcome = EportalClient.parse(#"dr1003({"result":0,"msg":"账号或密码不对"})"#)
        if case .failed(let reason) = outcome {
            #expect(reason.contains("密码"))
        } else {
            Issue.record("应判定为失败，实际 \(outcome)")
        }
    }

    @Test("门户说没有配置接入服务器 → 不支持静默登录")
    func unsupported() {
        #expect(EportalClient.parse(#"jsonpReturn({"result":0,"msg":"没有配置接入服务器！"})"#) == .unsupported)
    }

    @Test("老版 Dr.COM 页面标志")
    func legacy() {
        #expect(EportalClient.parse("Dr.COMWebLoginID_3.htm") == .success)
        if case .failed = EportalClient.parse("Dr.COMWebLoginID_2.htm") {} else {
            Issue.record("老版失败页应判定失败")
        }
    }
}
