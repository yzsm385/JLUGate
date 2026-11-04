import Foundation
import Darwin
import JLUGateCore

/// 自动找本机代理的本地端口：系统代理设置 + 常见客户端端口探测。
///
/// 目的：测速第三档（经住宅代理）不用用户手输端口。
public struct LocalProxyCandidate: Sendable, Equatable, Identifiable {
    public let label: String      // 例如 "Clash 7890"
    public let hostPort: String   // 例如 "127.0.0.1:7890"
    public var id: String { hostPort }
}

public enum LocalProxyDetector {
    /// 常见工具的默认端口（顺序即优先级）
    static let commonPorts: [(port: Int, label: String)] = [
        (7890, "Clash"), (7897, "Clash Verge"), (1087, "ClashX"),
        (6152, "Surge"), (6153, "Surge"), (1080, "SOCKS"),
        (8118, "Privoxy"), (8888, "Charles"), (9090, "Mihomo"), (20171, "V2Ray"),
    ]

    /// 系统代理里配置的 host:port（`scutil --proxy`），优先于端口猜测。
    public static func systemProxy() -> LocalProxyCandidate? {
        let output = PortOccupancy.shell("/usr/sbin/scutil", ["--proxy"])
        var host: String?
        var port: String?
        var label = "系统代理"
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("HTTPSProxy :") || text.hasPrefix("HTTPProxy :") {
                host = text.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("HTTPSPort :") || text.hasPrefix("HTTPPort :") {
                port = text.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("SOCKSProxy :") {
                host = text.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
                label = "SOCKS 代理"
            } else if text.hasPrefix("SOCKSPort :") {
                port = text.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        guard let host, let port, !host.isEmpty, Int(port) != nil else { return nil }
        return LocalProxyCandidate(label: label, hostPort: "\(host):\(port)")
    }

    /// 依次探测：系统代理 → 常见端口（能 TCP 连上才算）。
    public static func detect() -> LocalProxyCandidate? {
        if let system = systemProxy(), isListening(system.hostPort) { return system }
        for candidate in commonPorts where isListening("127.0.0.1:\(candidate.port)") {
            return LocalProxyCandidate(label: candidate.label,
                                       hostPort: "127.0.0.1:\(candidate.port)")
        }
        return nil
    }

    /// 200 毫秒内能建立 TCP 连接即认为有服务在听。
    public static func isListening(_ hostPort: String) -> Bool {
        let parts = hostPort.split(separator: ":")
        guard parts.count == 2,
              let port = UInt16(parts[1]),
              let address = IPv4Address(String(parts[0])) else { return false }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var flags = fcntl(fd, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        target.sin_addr = in_addr(s_addr: address.uint32BE.bigEndian)

        let result = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, 200) > 0 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
        return error == 0
    }
}
