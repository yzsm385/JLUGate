import Foundation
import Testing
@testable import JLUGateCore

@Suite("启动策略（记住过就不再打扰）")
struct LaunchPolicyTests {
    @Test("账号密码齐全且连过 → 不弹向导、静默自动连")
    func returningUserIsSilent() {
        #expect(LaunchPolicy.shouldShowWizard(hasAccount: true, hasPassword: true,
                                              linkRequiresStaticAddresses: false,
                                              profileIsComplete: true) == false)
        #expect(LaunchPolicy.shouldAutoConnect(hasAccount: true, hasPassword: true,
                                               linkRequiresStaticAddresses: false,
                                               profileIsComplete: true,
                                               everConnected: true,
                                               autoConnectEnabled: true))
    }

    @Test("从来没连过 → 不自动连（但也不弹向导，让用户自己点登录）")
    func neverConnectedDoesNotAutoStart() {
        #expect(LaunchPolicy.shouldAutoConnect(hasAccount: true, hasPassword: true,
                                               linkRequiresStaticAddresses: false,
                                               profileIsComplete: true,
                                               everConnected: false,
                                               autoConnectEnabled: true) == false)
    }

    @Test("用户关掉自动连接 → 不自动连")
    func respectsSwitch() {
        #expect(LaunchPolicy.shouldAutoConnect(hasAccount: true, hasPassword: true,
                                               linkRequiresStaticAddresses: false,
                                               profileIsComplete: true,
                                               everConnected: true,
                                               autoConnectEnabled: false) == false)
    }

    @Test("缺账号或缺密码 → 必须弹向导（这是唯一该打断用户的情况）")
    func missingCredentialsShowsWizard() {
        #expect(LaunchPolicy.shouldShowWizard(hasAccount: false, hasPassword: true,
                                              linkRequiresStaticAddresses: false,
                                              profileIsComplete: true))
        #expect(LaunchPolicy.shouldShowWizard(hasAccount: true, hasPassword: false,
                                              linkRequiresStaticAddresses: false,
                                              profileIsComplete: true))
    }

    @Test("有线/JLU.PC 还没填地址 → 弹向导；填过了就不弹")
    func staticAddresses() {
        #expect(LaunchPolicy.shouldShowWizard(hasAccount: true, hasPassword: true,
                                              linkRequiresStaticAddresses: true,
                                              profileIsComplete: false))
        #expect(LaunchPolicy.shouldShowWizard(hasAccount: true, hasPassword: true,
                                              linkRequiresStaticAddresses: true,
                                              profileIsComplete: true) == false)
    }

    @Test("JLU.WIFI / 自动：不需要静态地址，也不检查它")
    func portalNeedsNoAddresses() {
        #expect(LaunchPolicy.shouldAutoConnect(hasAccount: true, hasPassword: true,
                                               linkRequiresStaticAddresses: false,
                                               profileIsComplete: false,
                                               everConnected: true,
                                               autoConnectEnabled: true))
    }
}
