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

    // MARK: Dr.COM 4.0（吉大实测接口）

    @Test("吉大 Dr.COM 的 result=0 + 数字 msg + msga 也能解析")
    func numericFailure() {
        let text = #"dr1003({"result":0,"wopt":0,"msg":1,"uid":"zhangcyy5525","ss4":"fa63db4dc8cf","msga":"userid error1"})"#
        let outcome = EportalClient.parse(text)
        if case .failed(let reason) = outcome {
            #expect(reason.contains("密码"))
        } else {
            Issue.record("应判定为失败，实际 \(outcome)")
        }
    }

    @Test("数字代码映射到可读原因")
    func failureMessages() {
        #expect(EportalClient.failureMessage(code: 1, msga: "ldap auth error").contains("密码"))
        #expect(EportalClient.failureMessage(code: 3, msga: nil).contains("IP"))
        #expect(EportalClient.failureMessage(code: 4, msga: nil).contains("余额"))
        #expect(EportalClient.failureMessage(code: 5, msga: nil).contains("停机"))
        #expect(EportalClient.failureMessage(code: 6, msga: nil).contains("繁忙"))
        #expect(EportalClient.failureMessage(code: 9, msga: "boom").contains("9"))
    }

    @Test("账号只取 @ 前面的部分")
    func accountPrefix() {
        #expect(EportalClient.userAccount("zhangcyy5525@mails.jlu.edu.cn") == "zhangcyy5525")
        #expect(EportalClient.userAccount("  zhangcyy5525  ") == "zhangcyy5525")
        #expect(EportalClient.userAccount("@weird") == "@weird")
    }

    @Test("域名入口优先 https，再退回 http")
    func domainLoginURLs() throws {
        let urls = EportalClient().drcomLoginURLs(entry: try #require(URL(string: "http://net.jlu.edu.cn/")))
        #expect(urls.map(\.scheme) == ["https", "http"])
        #expect(urls.allSatisfy { $0.path == "/drcom/login" })
        #expect(urls.allSatisfy { $0.host == "net.jlu.edu.cn" })
    }

    @Test("网关 IP 入口会先试学校域名（证书只签了域名）")
    func ipEntryUsesSchoolHost() throws {
        let urls = EportalClient().drcomLoginURLs(entry: try #require(URL(string: "http://10.66.51.154/")))
        #expect(urls.first?.host == "net.jlu.edu.cn")
        #expect(urls.first?.scheme == "https")
        #expect(urls.last?.host == "10.66.51.154")
        #expect(urls.filter { $0.host == "10.66.51.154" }.allSatisfy { $0.scheme == "http" })
    }

    @Test("本机 / 回环入口不会去打扰真实学校门户")
    func loopbackStaysLocal() throws {
        let urls = EportalClient().drcomLoginURLs(entry: try #require(URL(string: "http://127.0.0.1:18080/portal")))
        #expect(urls.contains { $0.host == "127.0.0.1" && $0.port == 18080 })
        #expect(urls.allSatisfy { $0.host != "net.jlu.edu.cn" })
    }
}
