import Foundation
import Synchronization
import JLUGateCore

/// 测「认证通道」本身的质量：发真实的 20 字节 challenge，等 76 字节应答，量往返时间。
///
/// 为什么不用 ICMP/TCP ping：认证走的是 UDP 61440，绕代理时只有这条路径的延迟才算数。
/// 结果用来回答"全局代理还能不能用"——不是看模式，而是看这条路是否够快、是否丢包。
public struct AuthLivenessProbe: Sendable {
    public struct Sample: Sendable, Equatable {
        /// 绑定物理口（直连）
        public let direct: PingSummary
        /// 走系统默认路由（含代理/VPN）
        public let viaDefault: PingSummary
        public let server: String

        /// 经代理相对直连多出来的延迟（毫秒）；任一为空则 nil
        public var addedLatency: Double? {
            guard let d = direct.average, let v = viaDefault.average else { return nil }
            return v - d
        }

        /// 一句话结论
        public var verdict: String {
            guard let directAverage = direct.average else {
                return "直连没有回执：当前网络可能不是认证网络，或该接口发不出去。"
            }
            guard let viaAverage = viaDefault.average else {
                return "直连正常（\(Int(directAverage)) ms），但经代理没有回执——全局模式不可用。"
            }
            let delta = viaAverage - directAverage
            if viaDefault.loss > 0.34 {
                return "经代理丢包 \(Int(viaDefault.loss * 100))%：认证/保活极易超时被中断，建议改「配置」模式。"
            }
            if delta > 300 {
                return String(format: "经代理比直连慢 %.0f ms（%.0f → %.0f）：能通，但保活容易被判超时。",
                              delta, directAverage, viaAverage)
            }
            return String(format: "经代理只比直连慢 %.0f ms（%.0f → %.0f）：全局模式也能用。",
                          delta, directAverage, viaAverage)
        }
    }

    public init() {}

    public func measure(interface: InterfaceSnapshot?,
                        server: IPv4Address = PacketLayout.defaultServer,
                        attempts: Int = 3,
                        timeout: Duration = .seconds(2)) async -> Sample {
        let direct = await sample(interface: interface, server: server,
                                  attempts: attempts, timeout: timeout)
        let viaDefault = await sample(interface: nil, server: server,
                                      attempts: attempts, timeout: timeout)
        return Sample(direct: direct, viaDefault: viaDefault, server: server.description)
    }

    /// 发一次 challenge、等应答；成功返回毫秒，失败返回 nil。
    private func sample(interface: InterfaceSnapshot?, server: IPv4Address,
                        attempts: Int, timeout: Duration) async -> PingSummary {
        var latencies: [Double] = []
        for _ in 0..<attempts {
            if let rtt = await Self.roundTrip(interface: interface, server: server, timeout: timeout) {
                latencies.append(rtt)
            }
        }
        let label = interface.map { "直连 \($0.name)" } ?? "经默认出口"
        return PingSummary(host: "\(label) \(server)", latencies: latencies, attempted: attempts)
    }

    static func roundTrip(interface: InterfaceSnapshot?, server: IPv4Address,
                          timeout: Duration) async -> Double? {
        let channel = BSDChannel()
        defer { Task { await channel.close() } }
        let localIP = interface?.ipv4Address ?? IPv4Address("0.0.0.0")!
        let remote = IPv4Endpoint(host: server, port: PacketLayout.serverPort)
        // 先用真实的 61440：学校网关可能只认这个源端口；被占用时再退回临时端口。
        do {
            try await channel.open(localIP: localIP, localPort: PacketLayout.localPort,
                                   remote: remote, interfaceIndex: interface?.index ?? 0)
        } catch {
            do {
                try await channel.open(localIP: localIP, localPort: 0,
                                       remote: remote, interfaceIndex: interface?.index ?? 0)
            } catch {
                return nil
            }
        }

        let codec = DrcomCodec()
        guard let challenge = try? codec.makeChallenge(serial: UInt16.random(in: .min ... .max),
                                                       subtype: PacketLayout.Challenge.firstSubtype)
        else { return nil }
        let started = ContinuousClock.now
        do {
            try await channel.send(challenge)
            _ = try await channel.receive(timeout: timeout)
        } catch {
            return nil
        }
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }
}
