import Foundation
import Testing
@testable import JLUGateCore

@Suite("网口说明（这是谁的、干什么用）")
struct InterfaceNarratorTests {
    private func explain(_ name: String, hardware: String? = nil,
                         wifi: Bool = false, usb: Bool = false,
                         ipv4: String? = "192.0.2.10", apps: [String] = []) -> InterfaceExplanation {
        InterfaceNarrator.explain(name: name, hardwareName: hardware,
                                  isWireless: wifi, isUSB: usb, ipv4: ipv4, proxyApps: apps)
    }

    @Test("Wi-Fi：说明是谁的、能用来认证、JLU.WIFI 走它")
    func wifi() {
        let result = explain("en0", hardware: "Wi-Fi", wifi: true)
        #expect(result.purpose == .wifi)
        #expect(result.usableForAuthentication)
        #expect(result.title.contains("无线"))
        #expect(result.note.contains("JLU.WIFI"))
    }

    @Test("USB 网卡：提醒换口会改名、按 MAC 认")
    func usbEthernet() {
        let result = explain("en7", hardware: "USB 10/100/1000 LAN", usb: true)
        #expect(result.purpose == .usbEthernet)
        #expect(result.note.contains("MAC"))
    }

    @Test("雷雳网卡与内置有线区分开")
    func thunderbolt() {
        #expect(explain("en2", hardware: "Thunderbolt Ethernet").purpose == .thunderboltEthernet)
        #expect(explain("en5", hardware: "Ethernet").purpose == .wiredEthernet)
    }

    @Test("utun 说明是谁创建的")
    func tunnel() {
        let withApp = explain("utun4", apps: ["Shadowrocket"])
        #expect(withApp.purpose == .tunnel)
        #expect(withApp.owner.contains("Shadowrocket"))
        #expect(withApp.usableForAuthentication == false)

        let withoutApp = explain("utun4")
        #expect(withoutApp.owner.contains("VPN"))
    }

    @Test("回环 / Apple 内部 / AirDrop / 桥接 都不能拿来认证")
    func nonUsableInterfaces() {
        for name in ["lo0", "anpi0", "nan0", "awdl0", "llw0", "bridge0", "ap1"] {
            let result = explain(name)
            #expect(result.usableForAuthentication == false, "\(name) 不该被用来认证")
        }
        #expect(explain("lo0").purpose == .loopback)
        #expect(explain("anpi0").purpose == .appleInternal)
        #expect(explain("awdl0").purpose == .directLink)
        #expect(explain("bridge0").purpose == .bridge)
    }

    @Test("没有 IPv4 的有线口会提示先去配地址")
    func wiredWithoutAddress() {
        let result = explain("en9", hardware: "Ethernet", ipv4: nil)
        #expect(result.usableForAuthentication)
        #expect(result.note.contains("没有 IPv4"))
    }
}
