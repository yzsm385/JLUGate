import Foundation

/// 「网络体检」的结果模型与人话判定。
///
/// 名字参考 IPPure 一类工具：出口 IP、WebRTC、DNS 泄漏、Cloudflare、人机验证可达性。
/// 这里只放**纯数据 + 判定**，具体请求在 JLUGateNet 里做，便于单测。

public struct PublicIPSample: Sendable, Equatable, Identifiable {
    public let source: String
    public let ip: String
    public var id: String { source + ip }
    public init(source: String, ip: String) {
        self.source = source
        self.ip = ip
    }
}

public struct WebRTCSample: Sendable, Equatable {
    /// STUN 看到的公网地址（浏览器 WebRTC 泄漏检测拿到的就是它）
    public let publicIP: String?
    public let port: UInt16?
    public let server: String
    public let latencyMilliseconds: Int?
    public let note: String

    public init(publicIP: String?, port: UInt16?, server: String,
                latencyMilliseconds: Int?, note: String = "") {
        self.publicIP = publicIP
        self.port = port
        self.server = server
        self.latencyMilliseconds = latencyMilliseconds
        self.note = note
    }
}

public struct DNSLeakSample: Sendable, Equatable {
    /// 系统当前使用的 DNS（可能被代理接管）
    public let systemResolver: String?
    /// 系统 DNS 问 whoami.akamai.net 得到的"解析出口"
    public let systemEgress: String?
    /// 直连 8.8.8.8 问同一问题得到的出口（作为对照）
    public let publicEgress: String?
    /// 解析一个必然不存在的域名却拿到了地址 → 疑似被劫持/污染
    public let hijackSuspected: Bool

    public init(systemResolver: String?, systemEgress: String?,
                publicEgress: String?, hijackSuspected: Bool) {
        self.systemResolver = systemResolver
        self.systemEgress = systemEgress
        self.publicEgress = publicEgress
        self.hijackSuspected = hijackSuspected
    }

    public var summary: String {
        if let system = systemEgress, let pub = publicEgress {
            if system == pub { return "系统 DNS 与公共 DNS 出口一致（\(system)）" }
            return "系统 DNS 出口 \(system)，公共 DNS 出口 \(pub)：两者不同，说明解析走了两套路"
        }
        if let system = systemEgress {
            return "系统 DNS 出口 \(system)；公共 DNS 不可达（可能被墙或被代理接管）"
        }
        if let pub = publicEgress {
            return "系统 DNS 没有回执；公共 DNS 出口 \(pub)"
        }
        return "两种 DNS 都没有回执，可能整条 DNS 都被拦了"
    }
}

public struct EndpointCheck: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable, Equatable {
        case ok
        case blocked          // 连不上/超时
        case challenge        // 返回了人机验证挑战页
        case unexpected
    }

    public let name: String
    public let url: String
    public let state: State
    public let latencyMilliseconds: Int?
    public let detail: String?
    public var id: String { name }

    public init(name: String, url: String, state: State,
                latencyMilliseconds: Int? = nil, detail: String? = nil) {
        self.name = name
        self.url = url
        self.state = state
        self.latencyMilliseconds = latencyMilliseconds
        self.detail = detail
    }

    public var human: String {
        switch state {
        case .ok: "可用"
        case .blocked: "连不上"
        case .challenge: "会弹人机验证"
        case .unexpected: "返回了意外内容"
        }
    }
}

public enum InspectionVerdict {
    /// 出口 IP 是否"看起来像代理出口"（仅做提示，不下结论）。
    public static func ipHint(country: String?, sameAsLocal: Bool) -> String {
        if sameAsLocal { return "出口就是本机地址：流量没有走代理" }
        if let country {
            return "出口国家/地区 \(country)：流量已经过代理或异地节点"
        }
        return "出口与本机不同"
    }

    /// WebRTC 一句话。
    public static func webRTCHint(_ sample: WebRTCSample, localIP: String?) -> String {
        guard let publicIP = sample.publicIP else {
            return "没有拿到 STUN 回执：UDP 可能被完全挡住（这种情况反而不会泄漏）"
        }
        if let localIP, publicIP == localIP {
            return "STUN 看到的就是本机地址 \(publicIP)：WebRTC 会暴露真实 IP"
        }
        return "STUN 看到 \(publicIP)：这是浏览器 WebRTC 会暴露给网站的地址"
    }

    /// 人机验证是否"看起来被针对"。
    public static func captchaHint(_ checks: [EndpointCheck]) -> String {
        guard !checks.isEmpty else { return "还没检测" }
        let ok = checks.filter { $0.state == .ok }.count
        let challenged = checks.filter { $0.state == .challenge }.count
        let blocked = checks.filter { $0.state == .blocked }.count
        if blocked == checks.count { return "全部连不上：你的人机验证按钮在境外站点上很可能加载不出来" }
        if challenged > 0 { return "有 \(challenged) 个站点直接回人机验证页：这条出口被重点照顾了" }
        if ok == checks.count { return "都能正常加载，暂时没被针对" }
        return "\(ok)/\(checks.count) 可用，\(blocked) 个连不上"
    }
}
