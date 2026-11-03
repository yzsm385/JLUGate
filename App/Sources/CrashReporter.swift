import Foundation
import Darwin

/// 崩溃兜底：把致命信号 / ObjC 异常的栈写进 `~/Library/Logs/JLUGate/crash-stack.log`。
///
/// 目的很实际：用户机器上闪退时，系统 `.ips` 不一定方便拿到；有了这份栈就能直接定位。
enum CrashReporter {
    static func install() {
        NSSetUncaughtExceptionHandler(ObjCExceptionHandler)
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig, CrashSignalHandler)
        }
    }
}

/// 日志路径（C 字符串，信号处理里只能用这个）。
private enum CrashLogPath {
    nonisolated(unsafe) static let value: UnsafePointer<CChar> = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JLUGate", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return UnsafePointer(strdup(base.appendingPathComponent("crash-stack.log").path)!)
    }()
}

/// 无捕获的 C 函数：致命信号 → 打栈 → 退出。
private let CrashSignalHandler: @convention(c) (Int32) -> Void = { received in
    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 96)
    let count = backtrace(&frames, Int32(frames.count))
    let fd = open(CrashLogPath.value, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    if fd >= 0 {
        let header = "==== 致命信号 \(received) ====\n"
        _ = header.withCString { write(fd, $0, strlen($0)) }
        backtrace_symbols_fd(&frames, count, fd)
        close(fd)
    }
    exit(128 + received)
}

/// 无捕获的 C 函数：ObjC 未捕获异常 → 记录原因与调用栈。
private let ObjCExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    let text = """
    ==== ObjC 未捕获异常 ====
    \(exception.name.rawValue): \(exception.reason ?? "-")
    \(exception.callStackSymbols.joined(separator: "\n"))

    """
    if let file = fopen(CrashLogPath.value, "a") {
        fputs(text, file)
        fclose(file)
    }
}
