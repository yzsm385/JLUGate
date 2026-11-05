import Foundation

/// `Synchronization.Mutex`（macOS 15+）的向下兼容替身。
///
/// 为什么需要它：旧版适配包承诺支持 macOS 14，而 SwiftPM 的部署目标是整个包
/// 共用的——`Package.swift` 一旦按 14.0 编译，网络层里 `import Synchronization`
/// 就会报 "'Mutex' is only available in macOS 15.0 or newer"。
///
/// 为什么不直接用 `NSLock`：Swift 6 禁止在 async 上下文里裸 `lock()/unlock()`
///（跨 await 持锁会死锁），所以调用点统一用 `withLock` 闭包把临界区收窄。
/// 这个类保持和 `Mutex` 一样的 `init(_:)` + `withLock` 形状，调用点只改类型名。
///
/// 实现用 `NSLock` 而非 `os_unfair_lock`：临界区都很短，性能差异可以忽略，
/// 而 `NSLock` 在 14/15/26 上行为一致，不会因为系统版本分叉。
public final class CompatMutex<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(_ initialState: State) {
        self.state = initialState
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
