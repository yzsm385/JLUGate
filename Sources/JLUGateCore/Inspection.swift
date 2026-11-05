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
            if system == pub { return Copy.f("P45", system) }
            return Copy.f("P46", system, pub)
        }
        if let system = systemEgress {
            return Copy.f("P47", system)
        }
        if let pub = publicEgress {
            return Copy.f("P48", pub)
        }
        return Copy.t("P49")
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
        case .ok: Copy.t("P50")
        case .blocked: Copy.t("P51")
        case .challenge: Copy.t("P52")
        case .unexpected: Copy.t("P53")
        }
    }
}

public enum InspectionVerdict {
    /// 出口 IP 是否"看起来像代理出口"（仅做提示，不下结论）。
    public static func ipHint(country: String?, sameAsLocal: Bool) -> String {
        if sameAsLocal { return Copy.t("P54") }
        if let country {
            return Copy.f("P55", country)
        }
        return Copy.t("P56")
    }

    /// WebRTC 一句话。
    public static func webRTCHint(_ sample: WebRTCSample, localIP: String?) -> String {
        guard let publicIP = sample.publicIP else {
            return Copy.t("P57")
        }
        if let localIP, publicIP == localIP {
            return Copy.f("P58", publicIP)
        }
        return Copy.f("P59", publicIP)
    }

    /// 人机验证是否"看起来被针对"。
    public static func captchaHint(_ checks: [EndpointCheck]) -> String {
        guard !checks.isEmpty else { return Copy.t("P60") }
        let ok = checks.filter { $0.state == .ok }.count
        let challenged = checks.filter { $0.state == .challenge }.count
        let blocked = checks.filter { $0.state == .blocked }.count
        if blocked == checks.count { return Copy.t("P61") }
        if challenged > 0 { return Copy.f("P62", challenged) }
        if ok == checks.count { return Copy.t("P63") }
        return Copy.f("P64", ok, checks.count, blocked)
    }
}
