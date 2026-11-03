import Foundation
import Synchronization
import Testing
import JLUGateCore
@testable import JLUGateNet

// MARK: - 断言辅助

func expectEventually(_ description: String,
                     timeout: Duration = .seconds(3),
                     _ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("等待超时：\(description)")
}

// MARK: - 假时钟

/// 虚拟时间：`sleep` 只推进时钟（顺带让出一毫秒真时间，避免把 CPU 打满）。
final class FakeClock: Clock, @unchecked Sendable {
    private let instant = Mutex(ContinuousClock.now)

    func now() -> ContinuousClock.Instant {
        instant.withLock { $0 }
    }

    func sleep(for duration: Duration) async throws {
        instant.withLock { $0 = $0.advanced(by: duration) }
        try await Task.sleep(for: .milliseconds(1))
    }

    func advance(by duration: Duration) {
        instant.withLock { $0 = $0.advanced(by: duration) }
    }
}

// MARK: - 假通道

final class FakeChannel: DatagramChannel, @unchecked Sendable {
    struct State {
        var sent: [Data] = []
        var inbox: [Data] = []
        var opened = false
        var closed = false
        var openParameters: (localIP: IPv4Address, localPort: UInt16, remote: IPv4Endpoint, index: UInt32)?
    }

    private let state = Mutex(State())
    private let responder: @Sendable (Data) -> [Data]

    init(responder: @escaping @Sendable (Data) -> [Data] = { _ in [] }) {
        self.responder = responder
    }

    var sentFrames: [Data] { state.withLock { $0.sent } }
    var isClosed: Bool { state.withLock { $0.closed } }
    var isOpened: Bool { state.withLock { $0.opened } }
    var openParameters: (localIP: IPv4Address, localPort: UInt16, remote: IPv4Endpoint, index: UInt32)? {
        state.withLock { $0.openParameters }
    }

    func open(localIP: IPv4Address, localPort: UInt16,
              remote: IPv4Endpoint, interfaceIndex: UInt32) async throws {
        state.withLock {
            $0.opened = true
            $0.openParameters = (localIP, localPort, remote, interfaceIndex)
        }
    }

    func send(_ datagram: Data) async throws {
        let replies = responder(datagram)
        state.withLock {
            $0.sent.append(datagram)
            $0.inbox.append(contentsOf: replies)
        }
    }

    func receive(timeout: Duration) async throws -> Data {
        let next = state.withLock { state -> Data? in
            guard !state.inbox.isEmpty else { return nil }
            return state.inbox.removeFirst()
        }
        guard let next else { throw DrcomError.timeout(stage: "receive") }
        return next
    }

    func close() async {
        state.withLock { $0.closed = true }
    }
}

final class RecordingChannelFactory: ChannelFactory, @unchecked Sendable {
    private let channel: FakeChannel
    private let box = Mutex(0)

    init(channel: FakeChannel) {
        self.channel = channel
    }

    var madeCount: Int { box.withLock { $0 } }

    func makeChannel() -> any DatagramChannel {
        box.withLock { $0 += 1 }
        return channel
    }
}

// MARK: - 假网卡

struct FakeInterfaceProvider: InterfaceProvider {
    var interfaces: [InterfaceSnapshot]
    var route: RouteInfo?
    var configMethod: String?
    var gateway: String?

    func physicalInterfaces() -> [InterfaceSnapshot] { interfaces }
    func snapshot(of name: String) -> InterfaceSnapshot? { interfaces.first { $0.name == name } }
    func route(to host: IPv4Address) -> RouteInfo? { route }
    func configMethod(of name: String) -> String? { configMethod }
    func defaultGateway() -> String? { gateway }

    static let wired = FakeInterfaceProvider(
        interfaces: [InterfaceSnapshot(name: "en7", index: 12, ipv4: "192.0.2.10",
                                       mac: "02:00:00:00:00:01", isWireless: false, isUp: true,
                                       isUSB: true, linkLocalIPv4: "169.254.1.1",
                                       netmask: "255.255.255.0")],
        route: RouteInfo(destination: "10.100.61.3", gateway: "192.0.2.1", interface: "en7"),
        configMethod: "Manual",
        gateway: "192.0.2.1")
}

// MARK: - 用真实抓包字节应答的"网关"

enum RecordedGateway {
    static let session: FixturesLike.Session = FixturesLike.load()

    static func challengeReply(salt: String = "49cb720f") -> Data {
        var bytes = session.reply(length: 76)!
        let saltBytes = FixturesLike.bytes(hex: salt)
        bytes.replaceSubrange(0x04..<0x08, with: saltBytes)
        return Data(bytes)
    }

    static func loginSuccess() -> Data { Data(session.reply(length: 45)!) }
    static func loginFailure(reason: String = "ldap auth error") -> Data {
        var bytes = [UInt8](repeating: 0, count: 37)
        bytes[0] = 0x05
        bytes[3] = 0x05
        bytes[4] = 0x15
        let reasonBytes = Array(reason.utf8).prefix(37 - 0x14 - 2)
        bytes.replaceSubrange(0x14..<(0x14 + reasonBytes.count), with: reasonBytes)
        return Data(bytes)
    }

    static func keepAliveAReply() -> Data { Data(session.reply(length: 72)!) }

    /// 保活 B 应答：序号 +1，其余镜像请求（与抓包行为一致）。
    static func keepAliveBReply(to request: Data) -> Data {
        var bytes = [UInt8](request)
        guard bytes.count == 40 else { return request }
        bytes[0x05] = bytes[0x05] &+ 1
        bytes[0x18...0x1B] = [0x72, 0x46, 0xF8, 0x4C]
        return Data(bytes)
    }
}

enum FixturesLike {
    struct Session {
        let frames: [(dir: String, payload: [UInt8])]

        func reply(length: Int) -> [UInt8]? {
            frames.first { $0.dir == "s2c" && $0.payload.count == length }?.payload
        }
    }

    static func load() -> Session {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/session_sanitized.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["frames"] as? [[String: Any]] else {
            return Session(frames: [])
        }
        let frames: [(String, [UInt8])] = raw.compactMap { frame in
            guard let dir = frame["dir"] as? String, let hex = frame["hex"] as? String else { return nil }
            return (dir, bytes(hex: hex))
        }
        return Session(frames: frames)
    }

    static func bytes(hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            if let value = UInt8(hex[index..<next], radix: 16) { result.append(value) }
            index = next
        }
        return result
    }
}
