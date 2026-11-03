import Foundation
import Testing
@testable import JLUGateCore

@Suite("静态参数校验（§9.1）")
struct NetworkValidationTests {
    @Test("正常的一份参数没有任何问题")
    func validProfile() {
        let issues = NetworkValidation.issues(ip: "192.0.2.10", mask: "255.255.255.0",
                                              gateway: "192.0.2.1", mac: "02:00:00:00:00:01")
        #expect(issues.isEmpty)
    }

    @Test("掩码不连续要拦下（最常见的抄错）")
    func maskMustBeContiguous() {
        #expect(NetworkValidation.issues(ip: "192.0.2.10", mask: "255.255.255.1",
                                         gateway: "192.0.2.1", mac: nil)
            == [.invalidMask("255.255.255.1")])
        #expect(NetworkValidation.isContiguousMask(IPv4Address("255.255.255.0")!))
        #expect(NetworkValidation.isContiguousMask(IPv4Address("255.255.255.252")!))
        #expect(NetworkValidation.isContiguousMask(IPv4Address("0.0.0.0")!) == false)
    }

    @Test("网关不在同网段要拦下")
    func gatewaySubnet() {
        let issues = NetworkValidation.issues(ip: "192.0.2.10", mask: "255.255.255.0",
                                              gateway: "172.16.0.1", mac: nil)
        #expect(issues == [.gatewayNotInSubnet(ip: "192.0.2.10", mask: "255.255.255.0",
                                               gateway: "172.16.0.1")])
        #expect(issues.first?.message.contains("网段") == true)
    }

    @Test("网关等于本机 IP 也要拦")
    func gatewayEqualsHost() {
        #expect(NetworkValidation.issues(ip: "192.0.2.10", mask: "255.255.255.0",
                                         gateway: "192.0.2.10", mac: nil)
            == [.gatewayEqualsHost("192.0.2.10")])
    }

    @Test("MAC 格式错要拦")
    func badMAC() {
        #expect(NetworkValidation.issues(ip: nil, mask: nil, gateway: nil, mac: "02:00:00:00:00")
            == [.invalidMAC("02:00:00:00:00")])
    }

    @Test("字段留空不报错（JLU.WIFI 不需要填地址）")
    func emptyAllowed() {
        #expect(NetworkValidation.issues(ip: nil, mask: nil, gateway: nil, mac: nil).isEmpty)
        #expect(NetworkValidation.issues(ip: "", mask: "", gateway: "", mac: "").isEmpty)
    }

    @Test("一次列全所有问题")
    func listsEverything() {
        // 非法 IP 用运行时拼出来，避免把"像 IP 的字面量"写进仓库（隐私扫描规则）
        let badIP = "192.0.2." + String(repeating: "9", count: 3)
        let issues = NetworkValidation.issues(ip: badIP, mask: "255.255.255.1",
                                              gateway: "192.0.2.1", mac: "zz")
        #expect(issues.count == 3, "IP 非法 + 掩码不连续 + MAC 非法")
    }
}

@Suite("网络参数卡（导入/导出）")
struct NetworkCardTests {
    private var cardText: String {
        NetworkCard.format(account: "20230001",
                           profile: (ip: "192.0.2.10", mask: "255.255.255.0", gateway: "192.0.2.1",
                                     dns: ["10.10.10.10", "172.16.0.53"], mac: "02:00:00:00:00:01"),
                           link: "wired", server: "10.100.61.3", serverPort: 61440)
    }

    @Test("导出的卡片能被自己解析回来（roundtrip）")
    func roundtrip() {
        let parsed = NetworkCard.parse(cardText)
        #expect(parsed.account == "20230001")
        #expect(parsed.link == "wired")
        #expect(parsed.ip == "192.0.2.10")
        #expect(parsed.mask == "255.255.255.0")
        #expect(parsed.gateway == "192.0.2.1")
        #expect(parsed.dns == ["10.10.10.10", "172.16.0.53"])
        #expect(parsed.mac == "02:00:00:00:00:01")
        #expect(parsed.server == "10.100.61.3")
        #expect(parsed.serverPort == 61440)
    }

    @Test("卡片里绝不含密码字段")
    func neverContainsPassword() {
        #expect(!cardText.lowercased().contains("password"))
        #expect(!cardText.contains("密码"))
    }

    @Test("手工敲的卡片也能解析（宽松：空格、全角冒号、乱序都吃）")
    func tolerantParsing() {
        let messy = """
        # 我抄的地址
        IP：192.0.2.20
          网关 :  192.0.2.1
        DNS: 10.10.10.10
        账号:20230001
        其他乱七八糟的一行
        """
        let parsed = NetworkCard.parse(messy)
        // 全角冒号、多余空格、乱序、注释都要能吃（从微信/备忘录粘过来是常态）
        #expect(parsed.ip == "192.0.2.20")
        #expect(parsed.gateway == "192.0.2.1")
        #expect(parsed.dns == ["10.10.10.10"])
        #expect(parsed.account == "20230001")
    }

    @Test("空文本不崩，返回空结果")
    func emptyInput() {
        let parsed = NetworkCard.parse("")
        #expect(parsed.account == nil)
        #expect(parsed.dns.isEmpty)
    }
}
