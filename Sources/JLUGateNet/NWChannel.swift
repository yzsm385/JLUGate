import Foundation
import Network
import Synchronization
import JLUGateCore

/// `NWInterface` 在公开 API 里**无法构造**（只能从 `NWPath` 拿），
/// 所以用一个小注册表把 ifindex ↔ NWInterface 映射起来，通道与 PathMonitor 共用。
public final class NWInterfaceRegistry: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.jlugate.nwinterface-registry")
    private struct RegistryState: Sendable {
        var latestPath: NWPath?
        var started = false
    }
    private let state = CompatMutex(RegistryState())

    public init() {}

    public func start() {
        let alreadyStarted = state.withLock { state -> Bool in
            let was = state.started
            state.started = true
            return was
        }
        guard !alreadyStarted else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            self?.state.withLock { $0.latestPath = path }
        }
        monitor.start(queue: queue)
    }

    public func currentPath() -> NWPath? {
        state.withLock { $0.latestPath }
    }

    /// 等第一次 path 回调（最多 `timeout`），NW 通道在开工前要它。
    public func waitForPath(timeout: Duration = .seconds(1)) async -> NWPath? {
        start()
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let path = currentPath() { return path }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return currentPath()
    }

    public func interface(index: UInt32) async -> NWInterface? {
        guard let path = await waitForPath() else { return nil }
        return path.availableInterfaces.first { UInt32($0.index) == index }
    }

    public func snapshotInterfaces() async -> [(index: UInt32, name: String, type: NWInterface.InterfaceType)] {
        guard let path = await waitForPath() else { return [] }
        return path.availableInterfaces.map { (UInt32($0.index), $0.name, $0.type) }
    }
}

/// 注意：`Network` 框架自己也有一个 `IPv4Address`，本文件里一律写全名避免歧义。
public typealias CoreIPv4Address = JLUGateCore.IPv4Address

/// 生产通道：`NWParameters.udp` + `requiredInterface` + `requiredLocalEndpoint`（PLAN §6.1）。
public final class NWChannel: DatagramChannel, @unchecked Sendable {
    private let registry: NWInterfaceRegistry
    private let queue = DispatchQueue(label: "dev.jlugate.nwchannel")
    private let state = CompatMutex<NWConnection?>(nil)

    public init(registry: NWInterfaceRegistry) {
        self.registry = registry
    }

    public func open(localIP: CoreIPv4Address, localPort: UInt16,
                     remote: IPv4Endpoint, interfaceIndex: UInt32) async throws {
        guard let nwInterface = await registry.interface(index: interfaceIndex) else {
            throw DrcomError.channelFailure(
                "ifindex \(interfaceIndex) 不在 NWPath 的接口列表里（NWInterface 无法构造，必须来自路径状态）")
        }
        guard let localPortValue = NWEndpoint.Port(rawValue: localPort),
              let remotePortValue = NWEndpoint.Port(rawValue: remote.port) else {
            throw DrcomError.channelFailure("端口值不合法")
        }

        let parameters = NWParameters.udp
        parameters.requiredInterface = nwInterface
        parameters.prohibitedInterfaceTypes = [.loopback, .other]
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(localIP.description), port: localPortValue)

        let connection = NWConnection(
            host: NWEndpoint.Host(remote.host.description),
            port: remotePortValue,
            using: parameters)

        state.withLock { $0 = connection }

        try await Self.startAndWaitReady(connection, queue: queue, timeout: .seconds(3))
    }

    public func send(_ datagram: Data) async throws {
        guard let connection = currentConnection() else {
            throw DrcomError.channelFailure("通道未打开")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: datagram, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DrcomError.channelFailure("send 失败：\(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive(timeout: Duration) async throws -> Data {
        guard let connection = currentConnection() else {
            throw DrcomError.channelFailure("通道未打开")
        }

        // 两个任务赛跑：先收到数据 → 原样保留连接；先超时 → 才取消连接（丢弃旧 fd）。
        // 之前的写法在**收到数据后也 cancel()**，等于握手的第一个应答就把连接废掉，
        // 后面发登录包必然失败（真机上表现为"握手中"然后断开/闪退）。
        enum Outcome: Sendable {
            case data(Data)
            case timedOut
        }

        // 不用 TaskGroup：receieveMessage 的续体不能取消，放在 group 里会一直等它，
        // 反而让超时失效。这里用"先到者先 resume"的盒子，超时用独立计时任务。
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            let box = OneShotBox(continuation)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                box.resume(.timedOut)
            }
            box.attach(timer: timer)
            connection.receiveMessage { data, _, _, error in
                if error == nil, let data, !data.isEmpty {
                    box.resume(.data(data))
                } else {
                    box.resume(.timedOut)
                }
            }
        }

        switch outcome {
        case .data(let data):
            return data                      // 连接继续可用
        case .timedOut:
            connection.cancel()              // 超时才丢弃这条连接
            state.withLock { $0 = nil }
            throw DrcomError.timeout(stage: "receive")
        }
    }

    public func close() async {
        let connection = state.withLock { state -> NWConnection? in
            let current = state
            state = nil
            return current
        }
        connection?.cancel()
    }

    private func currentConnection() -> NWConnection? {
        state.withLock { $0 }
    }

    private static func startAndWaitReady(_ connection: NWConnection,
                                          queue: DispatchQueue,
                                          timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let box = OneShotContinuation(continuation)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            box.resume(returning: ())
                        case .failed(let error):
                            box.resume(throwing: DrcomError.channelFailure("NW 连接失败：\(error.localizedDescription)"))
                        case .cancelled:
                            box.resume(throwing: DrcomError.cancelled)
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DrcomError.timeout(stage: "open")
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }
}

/// 允许"只 resume 一次"的续体盒子（NW 的回调可能重复/迟到）。
/// 收包的容错版本：超时与数据走同一条续体（见 `receive`）。
private final class OneShotBox<Outcome: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Outcome, Never>) {
        self.continuation = continuation
    }

    func attach(timer: Task<Void, Never>) {
        lock.lock()
        let alreadyDone = continuation == nil
        if !alreadyDone { self.timer = timer }
        lock.unlock()
        if alreadyDone { timer.cancel() }
    }

    func resume(_ value: Outcome) {
        lock.lock()
        let continuation = self.continuation
        let timer = self.timer
        self.continuation = nil
        self.timer = nil
        lock.unlock()
        timer?.cancel()                 // 收到数据就别再等超时了
        continuation?.resume(returning: value)
    }
}

/// 允许"只 resume 一次"的续体盒子（NW 的回调可能重复/迟到）。
private final class OneShotContinuation<Success: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Success, Error>?

    init(_ continuation: CheckedContinuation<Success, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Success) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

public struct NWChannelFactory: ChannelFactory {
    private let registry: NWInterfaceRegistry

    public init(registry: NWInterfaceRegistry = NWInterfaceRegistry()) {
        self.registry = registry
    }

    public func makeChannel() -> any DatagramChannel {
        NWChannel(registry: registry)
    }
}

public struct BSDChannelFactory: ChannelFactory {
    public init() {}

    public func makeChannel() -> any DatagramChannel {
        BSDChannel()
    }
}
