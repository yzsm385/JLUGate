import Foundation

/// 下载停滞判定器（纯逻辑，不依赖时钟或网络，便于单元测试）。
///
/// 解决两个问题：
/// 1. 建连 / TLS 握手 / 302 重定向 / 等待首字节期间，不能按「0 B/s」立刻判停滞；
///    给予 `firstByteTimeout` 宽限，超时才报首字节超时。
/// 2. 收到首字节后，改用「连续 `stallWindow` 秒的平均速度」判定停滞，
///    避免单秒网络抖动或回调间隔导致误杀。
public struct DownloadStallDetector: Sendable {
    public enum Status: Equatable, Sendable {
        case waitingForFirstByte
        case active(recentBytesPerSecond: Double)
        case stalledFirstByte
        case stalledLowSpeed(averageBytesPerSecond: Double)
    }

    public let firstByteTimeout: TimeInterval
    public let stallWindow: TimeInterval
    public let minBytesPerSecond: Double

    private let startTime: TimeInterval
    private var firstByteTime: TimeInterval?
    private var samples: [(time: TimeInterval, receivedBytes: Int64)] = []
    private var lastSpeedSampleTime: TimeInterval
    private var lastSpeedSampleBytes: Int64 = 0
    private var lastRecentSpeed: Double = 0

    public init(
        startTime: TimeInterval = 0,
        firstByteTimeout: TimeInterval = 30,
        stallWindow: TimeInterval = 12,
        minBytesPerSecond: Double = 8_000
    ) {
        self.startTime = startTime
        self.firstByteTimeout = firstByteTimeout
        self.stallWindow = stallWindow
        self.minBytesPerSecond = minBytesPerSecond
        self.lastSpeedSampleTime = startTime
    }

    public mutating func evaluate(
        now: TimeInterval,
        receivedBytes: Int64,
        isCompleted: Bool = false
    ) -> Status {
        if receivedBytes <= 0 && firstByteTime == nil {
            if !isCompleted && (now - startTime) >= firstByteTimeout {
                return .stalledFirstByte
            }
            return .waitingForFirstByte
        }

        if firstByteTime == nil {
            firstByteTime = now
            samples.append((now, receivedBytes))
            lastSpeedSampleTime = now
            lastSpeedSampleBytes = receivedBytes
        } else {
            samples.append((now, receivedBytes))
        }

        let speedElapsed = now - lastSpeedSampleTime
        if speedElapsed >= 1.0 {
            lastRecentSpeed = Double(max(0, receivedBytes - lastSpeedSampleBytes)) / speedElapsed
            lastSpeedSampleTime = now
            lastSpeedSampleBytes = receivedBytes
        }

        // 保留刚好覆盖 stallWindow 的最老样本在 samples[0]
        while samples.count >= 2 && (now - samples[1].time) >= stallWindow {
            samples.removeFirst()
        }

        if !isCompleted,
           let firstByteTime,
           (now - firstByteTime) >= stallWindow,
           let oldest = samples.first {
            let windowElapsed = now - oldest.time
            if windowElapsed >= stallWindow {
                let avgSpeed = Double(max(0, receivedBytes - oldest.receivedBytes)) / windowElapsed
                if avgSpeed < minBytesPerSecond {
                    return .stalledLowSpeed(averageBytesPerSecond: avgSpeed)
                }
            }
        }

        return .active(recentBytesPerSecond: lastRecentSpeed)
    }
}
