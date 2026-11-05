import Testing
import Foundation
@testable import JLUGateCore

@Suite("网页认证入口：只信 jlu.edu.cn")
struct PortalTrustTests {
    @Test("学校域名和它的子域可信", arguments: [
        "https://login.jlu.edu.cn/portal",
        "https://jlu.edu.cn",
        "https://ip.jlu.edu.cn/pay",
        "HTTPS://LOGIN.JLU.EDU.CN/x",
        "https://login.jlu.edu.cn./x",
    ])
    func trusted(_ raw: String) throws {
        #expect(PortalTrust.isTrusted(try #require(URL(string: raw))))
    }

    @Test("相似域名、裸 IP、其他站一律不信", arguments: [
        "https://eviljlu.edu.cn/",
        "https://jlu.edu.cn.example.com/",
        "https://login.jlu.edu.cn.evil.net/",
        "http://10.100.61.3/",
        "http://192.168.1.1/",
        "https://jlu.edu.cn@evil.com/",
    ])
    func untrusted(_ raw: String) throws {
        #expect(!PortalTrust.isTrusted(try #require(URL(string: raw))))
    }

    @Test("没有 host 的地址不可信")
    func hostless() throws {
        #expect(!PortalTrust.isTrusted(try #require(URL(string: "file:///tmp/portal.html"))))
        #expect(!PortalTrust.isSchoolHost(""))
        #expect(!PortalTrust.isSchoolHost("   "))
    }

    @Test("大小写与末尾点号都按同一个域名处理")
    func normalization() {
        #expect(PortalTrust.isSchoolHost("JLU.EDU.CN"))
        #expect(PortalTrust.isSchoolHost("Login.JLU.edu.cn."))
        #expect(!PortalTrust.isSchoolHost("jlu.edu.com"))
        #expect(!PortalTrust.isSchoolHost("xjlu.edu.cn"))
    }
}
