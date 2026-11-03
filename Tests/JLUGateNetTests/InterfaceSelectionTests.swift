import Foundation
import Testing
import JLUGateCore
@testable import JLUGateNet

@Suite("选口：不许选回环 / 没有 IPv4 的口")
struct InterfaceSelectionTests {
    private let loopback = InterfaceSnapshot(name: "lo0", index: 1, ipv4: "127.0.0.1", mac: nil,
                                             isWireless: false, isUp: true)
    private let noAddress = InterfaceSnapshot(name: "en2", index: 6, ipv4: nil, mac: "02:00:00:00:00:05",
                                             isWireless: false, isUp: true)
    private let wifi = InterfaceSnapshot(name: "en0", index: 12, ipv4: "192.0.2.20",
                                         mac: "02:00:00:00:00:01", isWireless: true, isUp: true)

    @Test("回环与 Apple 内部接口都算虚拟口")
    func virtualNames() {
        for name in ["lo0", "anpi0", "utun4", "bridge0", "gif0", "stf0", "awdl0"] {
            #expect(VirtualInterfaceNames.isVirtual(name), "\(name) 应视为虚拟口")
        }
        for name in ["en0", "en7", "en12"] {
            #expect(VirtualInterfaceNames.isVirtual(name) == false, "\(name) 应视为物理口")
        }
    }

    @Test("lo0 虽然有 127.0.0.1，也不能用于认证")
    func loopbackUnusable() {
        #expect(loopback.isLoopback)
        #expect(loopback.isUsableForAuthentication == false)
        #expect(noAddress.isUsableForAuthentication == false, "没有 IPv4 的口不能选")
        #expect(wifi.isUsableForAuthentication)
    }

    @Test("协调器在 lo0 + 无地址口 + Wi-Fi 之间必须选 Wi-Fi")
    func coordinatorSkipsLoopback() async throws {
        let spy = ProviderSpy()
        let detector = FakeLinkDetector(drcomReachable: false)
        let provider = FakeInterfaceProvider(
            interfaces: [loopback, noAddress, wifi],
            route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en0"),
            configMethod: "Manual",
            gateway: "192.0.2.1")
        let coordinator = AuthCoordinator(
            configuration: AuthCoordinator.Configuration(
                preference: .jluWiFi,
                autoDetect: false,
                server: IPv4Endpoint(host: IPv4Address("10.100.61.3")!, port: 61440),
                dnsServers: [IPv4Address("10.10.10.10")!]),
            interfaces: provider,
            detector: detector,
            makeProvider: { link, snapshot in spy.make(link: link, snapshot: snapshot) })

        await coordinator.start()
        let request = try #require(spy.requests.first)
        #expect(request.1 == "en0", "必须是 en0，不能是 lo0；实际 \(request.1)")
        #expect(request.0 == .jluWiFi)
        await coordinator.stop()
    }

    @Test("引擎侧同样不会把 lo0 当出口")
    func engineSkipsLoopback() async throws {
        let provider = FakeInterfaceProvider(
            interfaces: [loopback, noAddress, wifi],
            route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en0"),
            configMethod: "Manual",
            gateway: "192.0.2.1")
        let channel = FakeChannel(responder: { datagram in
            switch datagram.count {
            case 20: return []
            default: return []
            }
        })
        let engine = DrcomEngine(
            configuration: EngineConfiguration(account: "20230001", password: "test-pass-2024",
                                               hostname: "test-mac.local"),
            codec: DrcomCodec(randomness: SeededRandomSource(seed: 3)),
            channelFactory: RecordingChannelFactory(channel: channel),
            interfaces: provider,
            clock: FakeClock())
        await engine.start()
        try await expectEventually("打开通道") { channel.isOpened }
        let parameters = try #require(channel.openParameters)
        #expect(parameters.localIP.description == "192.0.2.20", "必须绑 en0 的地址")
        #expect(parameters.index == 12)
        await engine.stop()
    }
}
