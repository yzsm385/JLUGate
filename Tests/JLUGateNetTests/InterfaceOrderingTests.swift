import Foundation
import Testing
@testable import JLUGateNet

@Suite("网口列表顺序：正在用的在前，其次有线优先")
struct InterfaceOrderingTests {
    private func snap(_ name: String, _ index: UInt32, ip: String?, wireless: Bool,
                      up: Bool = true) -> InterfaceSnapshot {
        InterfaceSnapshot(name: name, index: index, ipv4: ip, mac: "02:00:00:00:00:01",
                          isWireless: wireless, isUp: up)
    }

    @Test("正在连接的排第一，即使它是无线")
    func activeFirst() {
        let list = [snap("en7", 10, ip: "192.0.2.10", wireless: false),
                    snap("en0", 12, ip: "192.0.2.20", wireless: true)]
        let sorted = InterfaceOrdering.sorted(list, active: "en0")
        #expect(sorted.first?.name == "en0")
    }

    @Test("没有活动口时：有线有地址 > 有线无地址 > 无线有地址 > 无线无地址")
    func priority() {
        let list = [snap("en0", 1, ip: "192.0.2.20", wireless: true),
                    snap("en5", 2, ip: nil, wireless: false),
                    snap("en9", 3, ip: nil, wireless: true),
                    snap("en7", 4, ip: "192.0.2.10", wireless: false)]
        let names = InterfaceOrdering.sorted(list, active: nil).map(\.name)
        #expect(names == ["en7", "en5", "en0", "en9"])
    }

    @Test("虚拟口与回环排最后")
    func virtualLast() {
        let list = [snap("utun4", 1, ip: "10.8.0.1", wireless: false),
                    snap("en7", 2, ip: "192.0.2.10", wireless: false),
                    snap("lo0", 3, ip: "127.0.0.1", wireless: false)]
        let names = InterfaceOrdering.sorted(list, active: nil).map(\.name)
        #expect(names.first == "en7")
        #expect(names.last == "lo0" || names.last == "utun4")
    }
}
