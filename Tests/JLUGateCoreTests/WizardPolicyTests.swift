import Foundation
import Testing
@testable import JLUGateCore

@Suite("向导步骤（先账号 → 再方式 → 需要时才问地址）")
struct WizardPolicyTests {
    @Test("账号密码永远第一步，方式第二步")
    func orderAlwaysStartsWithCredentials() {
        for link in ["auto", "wired", "jluPC", "jluWiFi"] {
            let steps = WizardPolicy.steps(link: link, profileIsComplete: true)
            #expect(steps.prefix(2) == [.credentials, .link], "\(link) 的前两步应固定")
        }
    }

    @Test("JLU.WIFI 不需要静态地址，不问第三步")
    func portalNeedsNoAddresses() {
        #expect(WizardPolicy.steps(link: "jluWiFi", profileIsComplete: false) == [.credentials, .link])
    }

    @Test("有线 / JLU.PC 没填过地址 → 才出现第三步")
    func wiredNeedsAddressesWhenMissing() {
        #expect(WizardPolicy.steps(link: "wired", profileIsComplete: false)
                == [.credentials, .link, .network])
        #expect(WizardPolicy.steps(link: "jluPC", profileIsComplete: false)
                == [.credentials, .link, .network])
    }

    @Test("填过并记住了 → 不再问第二遍")
    func skipsWhenProfileComplete() {
        #expect(WizardPolicy.steps(link: "wired", profileIsComplete: true) == [.credentials, .link])
        #expect(WizardPolicy.steps(link: "jluPC", profileIsComplete: true) == [.credentials, .link])
    }

    @Test("自动模式不问地址（由探测决定链路）")
    func autoNeverAsks() {
        #expect(WizardPolicy.steps(link: "auto", profileIsComplete: false) == [.credentials, .link])
    }

    @Test("档案完整性：四项都得有")
    func completeness() {
        #expect(WizardPolicy.profileIsComplete(ip: "192.0.2.10", mask: "255.255.255.0",
                                               gateway: "192.0.2.1", mac: "02:00:00:00:00:01"))
        #expect(WizardPolicy.profileIsComplete(ip: "192.0.2.10", mask: "255.255.255.0",
                                               gateway: "192.0.2.1", mac: nil) == false)
        #expect(WizardPolicy.profileIsComplete(ip: " ", mask: "255.255.255.0",
                                               gateway: "192.0.2.1", mac: "02:00:00:00:00:01") == false)
    }
}
