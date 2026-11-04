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

private func macString(_ bytes: [UInt8]) -> String { MACAddress(bytes: bytes)!.description }

@Suite("MAC 取值：私有地址 vs 出厂地址")
struct MACSelectionTests {
    private var hardwareBytes: [UInt8] { [0xBC, 0xFC, 0xE7, 0xF3, 0x5B, 0x55] }
    private var privateBytes: [UInt8] { [0xF2, 0x2F, 0xBC, 0x61, 0x68, 0xE7] }

    @Test("系统套了私有 MAC 时，认证要用出厂 MAC")
    func prefersHardwareMAC() {
        let snapshot = InterfaceSnapshot(
            name: "en7", index: 12, ipv4: "192.0.2.10",
            mac: macString(privateBytes), isWireless: false, isUp: true,
            hardwareMAC: macString(hardwareBytes))
        #expect(snapshot.macAddress?.description == macString(privateBytes))
        #expect(snapshot.macForAuthentication?.description == macString(hardwareBytes))
    }

    @Test("没有出厂 MAC 时退回当前 MAC")
    func fallsBackToCurrentMAC() {
        let snapshot = InterfaceSnapshot(name: "en0", index: 4, ipv4: "192.0.2.10",
                                         mac: macString([0x02, 0, 0, 0, 0, 1]),
                                         isWireless: false, isUp: true)
        #expect(snapshot.macForAuthentication?.description == macString([0x02, 0, 0, 0, 0, 1]))
    }

    @Test("私有地址能识别出来（第一位是 02/06/0a/0e 等本地管理位）")
    func recognisesPrivateMAC() {
        for bytes: [UInt8] in [[0xF2, 0x2F, 0xBC, 0x61, 0x68, 0xE7],
                               [0x02, 0, 0, 0, 0, 1],
                               [0x6A, 0xE2, 0x85, 0xD7, 0xA5, 0x62],
                               [0xBE, 0, 0, 0, 0, 1]] {
            #expect(MACAddress(bytes: bytes)?.isLocallyAdministrated == true)
        }
        for bytes: [UInt8] in [[0xBC, 0xFC, 0xE7, 0xF3, 0x5B, 0x55],
                               [0x9C, 0x69, 0xD3, 0xA5, 0x3D, 0x30],
                               [0x14, 0x14, 0x4B, 0x81, 0x95, 0x0B]] {
            #expect(MACAddress(bytes: bytes)?.isLocallyAdministrated == false)
        }
    }

    @Test("登录包里的 MAC 用出厂地址，而不是系统的私有地址")
    func loginPacketUsesHardwareMAC() async throws {
        let snapshot = InterfaceSnapshot(
            name: "en7", index: 12, ipv4: "192.0.2.10",
            mac: macString(privateBytes), isWireless: false, isUp: true,
            hardwareMAC: macString(hardwareBytes))
        let provider = FakeInterfaceProvider(
            interfaces: [snapshot],
            route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7"),
            configMethod: "Manual", gateway: "192.0.2.1")
        let channel = FakeChannel(responder: { datagram in
            if datagram.count == 20 {
                var reply = Data([0x02, 0x03, 0x1d, 0x63])
                reply.append(Data(repeating: 0, count: 72))
                return [reply]
            }
            if datagram.count > 300, datagram.first == 0x03 {
                return [RecordedGateway.loginSuccess()]
            }
            return []
        })
        let engine = DrcomEngine(
            configuration: EngineConfiguration(account: "20230001", password: "test-pass-2024",
                                               hostname: "test-mac.local"),
            codec: DrcomCodec(randomness: SeededRandomSource(seed: 9)),
            channelFactory: RecordingChannelFactory(channel: channel),
            interfaces: provider,
            clock: FakeClock())
        await engine.start()
        try await expectEventually("发出登录包", timeout: .seconds(3)) {
            channel.sentFrames.contains { $0.count > 300 && $0.first == 0x03 }
        }
        let login = try #require(channel.sentFrames.first { $0.count > 300 && $0.first == 0x03 })
        // MAC 紧跟在密码段之后：偏移 = 322 + 密码字节数
        let macOffset = 322 + "test-pass-2024".utf8.count
        #expect([UInt8](login[macOffset..<(macOffset + 6)]) == hardwareBytes,
                "登录包里的 MAC 必须是出厂 MAC（偏移随密码长度平移）")
        await engine.stop()
    }

    @Test("引擎按出厂 MAC 选择网卡（私有 MAC 不再误报不匹配）")
    func engineMatchesHardwareMAC() async throws {
        let snapshot = InterfaceSnapshot(
            name: "en7", index: 12, ipv4: "192.0.2.10",
            mac: macString(privateBytes), isWireless: false, isUp: true,
            hardwareMAC: macString(hardwareBytes))
        let provider = FakeInterfaceProvider(
            interfaces: [snapshot],
            route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7"),
            configMethod: "Manual", gateway: "192.0.2.1")
        let channel = FakeChannel(responder: { _ in [] })
        let engine = DrcomEngine(
            configuration: EngineConfiguration(account: "20230001", password: "test-pass-2024",
                                               hostname: "test-mac.local",
                                               registeredMAC: MACAddress(bytes: hardwareBytes)),
            codec: DrcomCodec(randomness: SeededRandomSource(seed: 9)),
            channelFactory: RecordingChannelFactory(channel: channel),
            interfaces: provider,
            clock: FakeClock())
        await engine.start()
        try await expectEventually("打开通道（说明 MAC 校验通过）") { channel.isOpened }
        #expect(channel.isOpened)
        await engine.stop()
    }
}
