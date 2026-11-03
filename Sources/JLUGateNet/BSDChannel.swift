import Foundation
import Synchronization
import JLUGateCore

#if canImport(Darwin)
import Darwin
#endif

/// BSD 实现：`socket(AF_INET, SOCK_DGRAM)` → `IP_BOUND_IF` → `bind(localIP:61440)` → `connect`。
///
/// 为什么留着它（PLAN §6.1）：NW 通道在单测里建不起来（`NWInterface` 无法构造），
/// BSD 通道能对着 `127.0.0.1` 的模拟网关跑完整流程；生产仍优先用 NW。
public final class BSDChannel: DatagramChannel, @unchecked Sendable {
    private struct SocketState: Sendable {
        var fileDescriptor: Int32 = -1
        var port: UInt16 = 0
    }

    /// 用 `Mutex`（Synchronization）而不是 `NSLock`：Swift 6 禁止在 async 上下文里裸 lock()。
    private let state = Mutex(SocketState())

    public init() {}

    public var boundPort: UInt16 {
        state.withLock { $0.port }
    }

    /// 打开前先认一遍端口占用者，便于给出"先退出官方客户端"这种可执行提示（CHECKLIST §7）。
    public static func diagnosePort(_ port: UInt16) -> PortOccupancy {
        PortOccupancy.inspect(port: port)
    }

    public func open(localIP: IPv4Address, localPort: UInt16,
                     remote: IPv4Endpoint, interfaceIndex: UInt32) async throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw DrcomError.channelFailure("socket() 失败：\(Self.errnoText())")
        }

        // 出口钉在物理口上（保险，不替代路由；见 PLAN §6.5）
        var index = interfaceIndex
        guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
            let detail = Self.errnoText()
            Darwin.close(fd)
            throw DrcomError.channelFailure("IP_BOUND_IF(\(interfaceIndex)) 失败：\(detail)")
        }

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = localPort.bigEndian
        local.sin_addr = in_addr(s_addr: localIP.uint32BE.bigEndian)

        let bindResult = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            let code = errno
            let detail = Self.errnoText(code)
            Darwin.close(fd)
            if code == EADDRINUSE {
                let occupancy = PortOccupancy.inspect(port: localPort)
                switch occupancy {
                case .officialClient(let process, let pid):
                    throw DrcomError.officialClientRunning(process: process, pid: pid)
                case .other(let process):
                    throw DrcomError.localPortInUse(port: localPort, process: process)
                case .unknown:
                    throw DrcomError.localPortInUse(port: localPort, process: nil)
                }
            }
            throw DrcomError.channelFailure("bind(\(localIP):\(localPort)) 失败：\(detail)")
        }

        var remoteAddress = sockaddr_in()
        remoteAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remoteAddress.sin_family = sa_family_t(AF_INET)
        remoteAddress.sin_port = remote.port.bigEndian
        remoteAddress.sin_addr = in_addr(s_addr: remote.host.uint32BE.bigEndian)
        let connectResult = withUnsafePointer(to: &remoteAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            let detail = Self.errnoText()
            Darwin.close(fd)
            throw DrcomError.channelFailure("connect(\(remote)) 失败：\(detail)")
        }

        state.withLock {
            $0.fileDescriptor = fd
            $0.port = localPort
        }
    }

    public func send(_ datagram: Data) async throws {
        let fd = currentDescriptor()
        guard fd >= 0 else { throw DrcomError.channelFailure("通道未打开") }
        let sent = datagram.withUnsafeBytes { buffer -> Int in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
        guard sent == datagram.count else {
            throw DrcomError.channelFailure("send() 失败：\(Self.errnoText())")
        }
    }

    public func receive(timeout: Duration) async throws -> Data {
        let fd = currentDescriptor()
        guard fd >= 0 else { throw DrcomError.channelFailure("通道未打开") }

        let milliseconds = Int32(max(1, timeout.components.seconds * 1_000
            + Int64(timeout.components.attoseconds / 1_000_000_000_000_000)))
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds)
        if ready == 0 {
            throw DrcomError.timeout(stage: "receive")
        }
        if ready < 0 {
            if errno == EINTR { throw DrcomError.cancelled }
            throw DrcomError.channelFailure("poll() 失败：\(Self.errnoText())")
        }

        var buffer = [UInt8](repeating: 0, count: 65_535)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received >= 0 else {
            throw DrcomError.channelFailure("recv() 失败：\(Self.errnoText())")
        }
        return Data(buffer[0..<received])
    }

    public func close() async {
        let fd = state.withLock { state -> Int32 in
            let fd = state.fileDescriptor
            state.fileDescriptor = -1
            state.port = 0
            return fd
        }
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    private func currentDescriptor() -> Int32 {
        state.withLock { $0.fileDescriptor }
    }

    static func errnoText(_ code: Int32 = errno) -> String {
        guard let message = strerror(code) else { return "errno \(code)" }
        return String(decoding: UnsafeBufferPointer(start: message, count: strlen(message)).map { UInt8(bitPattern: $0) },
                      as: UTF8.self)
    }
}

/// 61440 被谁占着（决定给用户哪一句提示）。只看、不杀。
public enum PortOccupancy: Sendable, Equatable {
    case officialClient(process: String, pid: Int32?)
    case other(process: String)
    case unknown

    private static let officialNames = ["drcomauth", "DrClientNS", "DrClient", "DrCom"]

    public static func inspect(port: UInt16) -> PortOccupancy {
        #if canImport(Darwin)
        let output = shell("/usr/sbin/lsof", ["-nP", "-iUDP:\(port)"])
        guard !output.isEmpty else { return .unknown }
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2 else { continue }
            let process = String(columns[0])
            let pid = Int32(columns[1])
            if officialNames.contains(where: { process.hasPrefix($0) }) {
                return .officialClient(process: process, pid: pid)
            }
            return .other(process: process)
        }
        return .unknown
        #else
        return .unknown
        #endif
    }

    /// 只用于 `lsof` / `route` / `ipconfig` 这类**参数固定**的只读诊断，
    /// 不拼接 shell 字符串，也不把用户输入塞进 argv。
    static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
