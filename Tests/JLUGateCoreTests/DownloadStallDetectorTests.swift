import Testing
@testable import JLUGateCore

@Suite("下载停滞判定器（首字节宽限 + 滑动低速窗口）")
struct DownloadStallDetectorTests {
    @Test("建连/等待首字节期间（即使超过 1 秒）不误判停滞，超时才触发")
    func firstByteGracePeriod() {
        var detector = DownloadStallDetector(
            startTime: 0,
            firstByteTimeout: 25,
            stallWindow: 12,
            minBytesPerSecond: 8_000
        )

        // 1~24 秒未收到任何字节：必须处于等待首字节，不能误杀
        for t in stride(from: 1.0, through: 24.0, by: 1.0) {
            let status = detector.evaluate(now: t, receivedBytes: 0)
            #expect(status == .waitingForFirstByte)
        }

        // 达到 25 秒仍未收到首字节：触发首字节超时
        let timeoutStatus = detector.evaluate(now: 25.0, receivedBytes: 0)
        #expect(timeoutStatus == .stalledFirstByte)
    }

    @Test("收到首字节后，短暂 1~3 秒零写入（网络抖动）不误杀")
    func transientJitterDoesNotTriggerStall() {
        var detector = DownloadStallDetector(
            startTime: 0,
            firstByteTimeout: 25,
            stallWindow: 12,
            minBytesPerSecond: 8_000
        )

        // 第 3 秒收到首字节（模拟 DNS/TLS/302 耗时）
        #expect(detector.evaluate(now: 1.0, receivedBytes: 0) == .waitingForFirstByte)
        #expect(detector.evaluate(now: 2.0, receivedBytes: 0) == .waitingForFirstByte)

        var bytes: Int64 = 100_000
        // 3~8 秒正常高速下载（100 KB/s）
        for t in 3...8 {
            bytes += 100_000
            let status = detector.evaluate(now: Double(t), receivedBytes: bytes)
            guard case .active = status else {
                Issue.record("预期 active，实际 \(status)")
                return
            }
        }

        // 9~11 秒完全卡顿 3 秒（0 字节增量）
        for t in 9...11 {
            let status = detector.evaluate(now: Double(t), receivedBytes: bytes)
            guard case .active = status else {
                Issue.record("瞬时抖动不应该触发停滞，实际 \(status)")
                return
            }
        }

        // 12~20 秒恢复下载（50 KB/s）
        for t in 12...20 {
            bytes += 50_000
            let status = detector.evaluate(now: Double(t), receivedBytes: bytes)
            guard case .active = status else {
                Issue.record("恢复后不应触发停滞，实际 \(status)")
                return
            }
        }
    }

    @Test("连续低速超过窗口时长后触发停滞")
    func sustainedLowSpeedTriggersStall() {
        var detector = DownloadStallDetector(
            startTime: 0,
            firstByteTimeout: 25,
            stallWindow: 12,
            minBytesPerSecond: 8_000
        )

        var bytes: Int64 = 16_384
        // 1~12 秒每秒仅滴 1 KB（远低于 8 KB/s），在第 13 秒满 12 秒窗口时触发
        for t in 1...12 {
            bytes += 1_000
            let status = detector.evaluate(now: Double(t), receivedBytes: bytes)
            guard case .active = status else {
                Issue.record("窗口未满时不应提前触发，t=\(t) status=\(status)")
                return
            }
        }

        bytes += 1_000
        let finalStatus = detector.evaluate(now: 13.0, receivedBytes: bytes)
        guard case .stalledLowSpeed(let avgSpeed) = finalStatus else {
            Issue.record("预期 stalledLowSpeed，实际 \(finalStatus)")
            return
        }
        #expect(avgSpeed < 8_000)
        #expect(avgSpeed >= 900 && avgSpeed <= 1_100)
    }

    @Test("已下完时不触发停滞")
    func completedDownloadDoesNotTriggerStall() {
        var detector = DownloadStallDetector(
            startTime: 0,
            firstByteTimeout: 25,
            stallWindow: 12,
            minBytesPerSecond: 8_000
        )

        #expect(detector.evaluate(now: 1.0, receivedBytes: 50_000, isCompleted: true) != .stalledFirstByte)
        let status = detector.evaluate(now: 20.0, receivedBytes: 50_000, isCompleted: true)
        guard case .active = status else {
            Issue.record("已完成不应判停滞，实际 \(status)")
            return
        }
    }
}
