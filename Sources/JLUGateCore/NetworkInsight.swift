import Foundation

/// 面向用户的字段解释：把"终端里才看得懂"的东西翻译成人话。
public enum FieldGuide {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: String
        public let term: String
        public let explanation: String
    }

    /// 每个字段是什么、为什么学校/客户端在意它。
    public static let entries: [Entry] = [
        .init(id: "interface", term: Copy.t("P65"),
              explanation: Copy.t("P66")),
        .init(id: "mac", term: Copy.t("P67"),
              explanation: Copy.t("P68")),
        .init(id: "ipv4", term: Copy.t("P69"),
              explanation: Copy.t("P70")),
        .init(id: "mask", term: Copy.t("P71"),
              explanation: Copy.t("P72")),
        .init(id: "gateway", term: Copy.t("P73"),
              explanation: Copy.t("P74")),
        .init(id: "dns", term: "DNS",
              explanation: Copy.t("P75")),
        .init(id: "linklocal", term: Copy.t("P76"),
              explanation: Copy.t("P77")),
        .init(id: "route", term: Copy.t("P78"),
              explanation: Copy.t("P79")),
        .init(id: "tun", term: "TUN / VPN",
              explanation: Copy.t("P80")),
        .init(id: "wireless", term: Copy.t("P81"),
              explanation: Copy.t("P82")),
        .init(id: "speed", term: Copy.t("P83"),
              explanation: Copy.t("P84")),
        .init(id: "ping", term: Copy.t("P85"),
              explanation: Copy.t("P86")),
    ]

    public static func explanation(for id: String) -> String? {
        entries.first { $0.id == id }?.explanation
    }
}

/// 吞吐量换算与展示。
public enum Throughput {
    public static func bitsPerSecond(bytes: Int, seconds: Double) -> Double {
        guard seconds > 0, bytes > 0 else { return 0 }
        return Double(bytes) * 8 / seconds
    }

    public static func megabitsPerSecond(bytes: Int, seconds: Double) -> Double {
        bitsPerSecond(bytes: bytes, seconds: seconds) / 1_000_000
    }

    /// 12.3 Mbps（顺便给出 MB/s，避免用户把 Mb 和 MB 搞混）
    public static func format(megabitsPerSecond mbps: Double) -> String {
        guard mbps > 0 else { return "—" }
        let megabytes = mbps / 8
        return String(format: "%.1f Mbps（≈ %.1f MB/s）", mbps, megabytes)
    }
}

/// 一次 Ping 的统计（多次探测）。
public struct PingSummary: Sendable, Equatable {
    public let host: String
    public let latencies: [Double]   // 毫秒，成功的那些
    public let attempted: Int

    public init(host: String, latencies: [Double], attempted: Int) {
        self.host = host
        self.latencies = latencies
        self.attempted = attempted
    }

    public var loss: Double {
        guard attempted > 0 else { return 1 }
        return Double(attempted - latencies.count) / Double(attempted)
    }

    public var minimum: Double? { latencies.min() }
    public var maximum: Double? { latencies.max() }
    public var average: Double? {
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    public var description: String {
        guard let average else {
            return Copy.f("P87", host, Int(loss * 100))
        }
        let min = minimum ?? average
        let max = maximum ?? average
        return String(format: Copy.t("P88"),
                      host, average, min, max, loss * 100)
    }
}
