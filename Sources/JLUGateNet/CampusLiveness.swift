import Foundation
import JLUGateCore

/// 判断"链路是否还活着"的校内优先探测。
///
/// 为什么需要它：引擎在保活无应答时会先做一次"网络到底通不通"的确认，
/// 以前用的是 `connectivitycheck.gstatic.com` / `cp.cloudflare.com`——
/// 这两个在吉大网络里经常被拦或解析失败，于是**网络明明通着也被判成断线**，
/// 表现就是"挂着没动，它自己从已连接跳到失败"。
///
/// 现在按顺序确认：
/// 1. 校内 DNS（默认 10.10.10.10）能应答 → 在校园网、链路活着；
/// 2. 认证服务器 10.100.61.3:61440 对 challenge 有回执 → 网关活着；
/// 3. 都失败才认为真的断了。
public struct CampusLiveness: Sendable {
    public init() {}

    public func probe(interface: InterfaceSnapshot,
                      server: IPv4Address,
                      dns: IPv4Address?) async -> Bool {
        guard let ip = interface.ipv4Address else { return false }
        if await dnsReachable(interface: interface, localIP: ip,
                              dns: dns ?? IPv4Address("10.10.10.10")!) {
            return true
        }
        return await serverReachable(interface: interface, localIP: ip, server: server)
    }

    private func dnsReachable(interface: InterfaceSnapshot, localIP: IPv4Address,
                              dns: IPv4Address) async -> Bool {
        let channel = BSDChannel()
        do {
            try await channel.open(localIP: localIP, localPort: 0,
                                   remote: IPv4Endpoint(host: dns, port: 53),
                                   interfaceIndex: interface.index)
            let query = DNSPacket.makeQuery(name: "www.baidu.com", id: 0x4A21)
            try await channel.send(Data(query))
            let reply = try await channel.receive(timeout: .milliseconds(1200))
            await channel.close()
            return !reply.isEmpty
        } catch {
            await channel.close()
            return false
        }
    }

    private func serverReachable(interface: InterfaceSnapshot, localIP: IPv4Address,
                                 server: IPv4Address) async -> Bool {
        let channel = BSDChannel()
        do {
            try await channel.open(localIP: localIP, localPort: 0,
                                   remote: IPv4Endpoint(host: server,
                                                        port: PacketLayout.serverPort),
                                   interfaceIndex: interface.index)
            let challenge = try DrcomCodec().makeChallenge(serial: 0x1357,
                                                           subtype: PacketLayout.Challenge.firstSubtype)
            try await channel.send(challenge)
            _ = try await channel.receive(timeout: .milliseconds(1200))
            await channel.close()
            return true
        } catch {
            await channel.close()
            return false
        }
    }
}
