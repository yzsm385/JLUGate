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
        .init(id: "interface", term: "网口（en0 / en7）",
              explanation: "系统给每块网卡起的名字。USB 网卡换个口就可能改名，所以认证要按 MAC 认，不按名字认。"),
        .init(id: "mac", term: "MAC 地址",
              explanation: "网卡的物理地址，出厂就固定。学校按 MAC 登记你的接入权限——换了网卡或 USB 口，必须去学校平台重新登记，否则认证一定失败。"),
        .init(id: "ipv4", term: "IPv4 地址",
              explanation: "这台电脑在校园网里的门牌号。学校按宿舍端口分配固定地址，所以必须手工照抄，不能用 DHCP 自动拿到的。"),
        .init(id: "mask", term: "子网掩码",
              explanation: "说明这个门牌号里哪一段是「本宿舍楼」、哪一段是「外面」。填错就会把网关当外人，直接连不上。"),
        .init(id: "gateway", term: "网关",
              explanation: "出宿舍楼的第一跳（路由器）。必须和 IP 在同一个网段，否则发出去也没人接。"),
        .init(id: "dns", term: "DNS",
              explanation: "把网址翻译成 IP 的服务。被代理劫持时会把所有域名解析成 198.18.x.x 这类假地址。"),
        .init(id: "linklocal", term: "链路本地地址（169.254.x.x）",
              explanation: "网卡没拿到地址时自己编的临时地址。登录包里也要带上它，没有就填 0。"),
        .init(id: "route", term: "路由 / 出口",
              explanation: "数据从哪块网卡出去。如果 10.100.61.3 的出口是 utun 开头的虚拟网卡，说明流量被代理截走了，认证包到不了学校网关。"),
        .init(id: "tun", term: "TUN / VPN",
              explanation: "代理软件（Clash、Surge、WireGuard 等）创建的虚拟网卡。它抢走默认路由后，所有流量都先进代理；必须在代理规则里把 10.0.0.0/8 设为直连。"),
        .init(id: "wireless", term: "无线 / 有线",
              explanation: "认证走哪条链路。有线与 JLU.PC 共用同一套地址和账号；JLU.WIFI 是网页认证，另外算。"),
        .init(id: "speed", term: "测速（Mbps）",
              explanation: "Mb 是比特、MB 是字节，1 字节 = 8 比特。运营商说的 100M 宽带指 100 Mbps，下载文件时看到的 MB/s 要除以 8。"),
        .init(id: "ping", term: "Ping 延迟（ms）",
              explanation: "一个来回要多久。校园网内一般 < 10ms；绕到代理或VPN会明显变高，丢包则说明链路不稳。"),
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
            return "\(host)：全部超时（丢包 \(Int(loss * 100))%）"
        }
        let min = minimum ?? average
        let max = maximum ?? average
        return String(format: "%@：平均 %.0f ms（最小 %.0f / 最大 %.0f，丢包 %.0f%%）",
                      host, average, min, max, loss * 100)
    }
}
