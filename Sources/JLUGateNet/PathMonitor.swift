import Foundation
import Network
import JLUGateCore

/// 网络跃迁（换网卡、路由变化、TUN 接管）。引擎据此作废当前 epoch（PLAN §6.3 / §8.6）。
public enum PathEvent: Sendable, Equatable {
    case becameSatisfied
    case becameUnsatisfied
    /// 物理口集合或默认出口变了 —— 必须重新 discover，不能复用旧快照。
    case interfacesChanged(current: [String])
}

/// `NWPathMonitor` 的 AsyncStream 包装。
///
/// 只做"通知"，不做判断：是否要重连由 `DrcomEngine` 决定，避免两层各自有一套阈值。
public final class PathMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.jlugate.pathmonitor")
    private let lock = NSLock()
    private var lastNames: [String] = []
    private var lastSatisfied: Bool?

    public init() {}

    public func events() -> AsyncStream<PathEvent> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                // 去重：同一块网卡可能被 NWPath 报两次，重复会导致无谓的"重新发现 + 重连"
                let names = Array(Set(path.availableInterfaces
                    .filter { !VirtualInterfaceNames.isVirtual($0.name) }
                    .map(\.name)))
                    .sorted()
                self.lock.lock()
                let previousNames = self.lastNames
                let previousSatisfied = self.lastSatisfied
                self.lastNames = names
                self.lastSatisfied = path.status == .satisfied
                self.lock.unlock()

                if previousSatisfied != (path.status == .satisfied) {
                    continuation.yield(path.status == .satisfied ? .becameSatisfied : .becameUnsatisfied)
                }
                if !previousNames.isEmpty, previousNames != names {
                    continuation.yield(.interfacesChanged(current: names))
                }
            }
            monitor.start(queue: queue)
            continuation.onTermination = { [monitor] _ in
                monitor.cancel()
            }
        }
    }

    public func cancel() {
        monitor.cancel()
    }
}
