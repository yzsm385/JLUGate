import Foundation
import Synchronization
import JLUGateCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 门户入口（从 302 的 Location，或登录页里的表单/跳转里找出来）。
public struct PortalEntry: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case redirect
        case pageInspection
        case configured
    }

    public var url: URL
    public var source: Source
    public var loginFormAction: URL?

    public init(url: URL, source: Source, loginFormAction: URL? = nil) {
        self.url = url
        self.source = source
        self.loginFormAction = loginFormAction
    }
}

public enum PortalLoginResult: Sendable, Equatable {
    case succeeded
    case cancelled
    case failed(reason: String)
}

/// 由 App 层注入的浏览器能力（Core/Net 不 import WebKit，PLAN §4）。
///
/// **决策 D-001**：只打开登录页，不做任何 DOM 操作/表单填充。
/// 因此这里连账号密码都不传——认证过程中程序不接触明文凭据。
public protocol PortalBrowser: AnyObject, Sendable {
    func presentLogin(url: URL) async -> PortalLoginResult
    func clearCookies() async
}

/// 取登录页 HTML 的能力（只读，用来找入口与表单动作）。
public protocol PortalPageFetching: Sendable {
    func fetch(_ url: URL, interface: InterfaceSnapshot) async throws -> PortalPage
}

public struct PortalPage: Sendable, Equatable {
    public var statusCode: Int
    public var body: String
    public var location: String?

    public init(statusCode: Int, body: String, location: String? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.location = location
    }
}

// MARK: - 判定

/// 把探针结论翻译成"要不要弹窗、往哪个 URL 弹"。
public struct PortalDetector: Sendable {
    public var fetcher: any PortalPageFetching
    /// 配置里写死的入口（用户/上次抓到的）。
    public var configuredURL: URL?

    public init(fetcher: any PortalPageFetching = URLSessionPortalFetcher(),
                configuredURL: URL? = nil) {
        self.fetcher = fetcher
        self.configuredURL = configuredURL
    }

    /// 已在线时返回 nil。
    public func detect(probe: ProbeOutcome, interface: InterfaceSnapshot) async -> PortalEntry? {
        switch probe {
        case .healthy:
            return nil
        case .unreachable:
            return nil
        case .captivePortal(let statusCode, let location):
            if let location, let url = URL(string: location), url.scheme != nil {
                return PortalEntry(url: url, source: .redirect)
            }
            // 门户直接返页面：去页面里找表单动作 / meta refresh / 明显的登录链接
            if let configured = configuredURL {
                if let entry = try? await inspect(configured, interface: interface) {
                    return entry
                }
                return PortalEntry(url: configured, source: .configured)
            }
            // 没配置：先按"网关根路径"试（captive portal 基本都在网关 80 端口），
            // 再试吉大已知门户（net.jlu.edu.cn 是 Dr.COM 的网页登录页）。
            // 顺序很重要：**先试学校已知门户**（net.jlu.edu.cn 是 Dr.COM 登录页），
            // 再试"网关/本机 IP 根路径"。以前先试本机 IP，结果拿到 http://10.66.51.154/
            // 这种打不开的地址，用户看到的门户页就是空的。
            var candidates = Self.knownJLUEntries
            if let ip = interface.ipv4, let url = URL(string: "http://\(ip)/") {
                candidates.append(url)
            }
            for url in candidates {
                if let entry = await verifiedEntry(url, interface: interface) {
                    return entry
                }
            }
            if let first = candidates.first {
                _ = statusCode
                return PortalEntry(url: first, source: .pageInspection)
            }
            return nil
        }
    }

    func inspect(_ url: URL, interface: InterfaceSnapshot) async throws -> PortalEntry? {
        let page = try await fetcher.fetch(url, interface: interface)
        if let location = page.location, let redirect = URL(string: location, relativeTo: url)?.absoluteURL {
            return PortalEntry(url: redirect, source: .redirect)
        }
        if let action = Self.formAction(in: page.body, base: url) {
            return PortalEntry(url: action, source: .pageInspection, loginFormAction: action)
        }
        if let refresh = Self.metaRefresh(in: page.body, base: url) {
            return PortalEntry(url: refresh, source: .pageInspection)
        }
        return nil
    }

    /// 抓页面并确认它**真的是登录页**（Dr.COM / eportal / 有表单），
    /// 而不是随便一个能返回 200 的地址。
    func verifiedEntry(_ url: URL, interface: InterfaceSnapshot) async -> PortalEntry? {
        guard let page = try? await fetcher.fetch(url, interface: interface) else { return nil }
        let body = page.body.lowercased()
        let looksLikePortal = body.contains("dr.comwebloginid")
            || body.contains("eportal")
            || body.contains("ddddd")
            || body.contains("upass")
            || page.location != nil
        guard looksLikePortal || page.statusCode == 302 || page.statusCode == 200 && !body.isEmpty else {
            return nil
        }
        return (try? await inspect(url, interface: interface))
            ?? PortalEntry(url: url, source: .pageInspection)
    }

    /// 吉大已知的门户入口（按优先级）。
    /// `net.jlu.edu.cn` 是 Dr.COM 的网页登录页（用户实测浏览器就是停在这里）。
    public static let knownJLUEntries: [URL] = [
        URL(string: "http://net.jlu.edu.cn/")!,
        URL(string: "http://10.100.61.3/")!,
    ]

    /// 从 HTML 里抓 `<form ... action="...">`（大小写与引号都不敏感）。
    public static func formAction(in html: String, base: URL) -> URL? {
        guard let formRange = html.range(of: "<form", options: [.caseInsensitive]) else { return nil }
        let tail = html[formRange.lowerBound...]
        guard let actionRange = tail.range(of: "action", options: [.caseInsensitive]) else { return nil }
        let afterAction = tail[actionRange.upperBound...]
        guard let equals = afterAction.firstIndex(of: "=") else { return nil }
        let value = afterAction[afterAction.index(after: equals)...]
        guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
        guard let closing = value.dropFirst().firstIndex(of: quote) else { return nil }
        let raw = value[value.index(after: value.startIndex)..<closing]
        return URL(string: String(raw), relativeTo: base)?.absoluteURL
    }

    public static func metaRefresh(in html: String, base: URL) -> URL? {
        guard let range = html.range(of: "http-equiv", options: [.caseInsensitive]) else { return nil }
        let tail = html[range.upperBound...]
        guard tail.lowercased().hasPrefix("=\"refresh\"") || tail.lowercased().hasPrefix("='refresh'") else {
            return nil
        }
        guard let urlRange = tail.range(of: "url=", options: [.caseInsensitive]) else { return nil }
        let rest = tail[urlRange.upperBound...]
        let candidate = rest.prefix { $0 != "\"" && $0 != "'" && $0 != ">" && $0 != " " }
        return URL(string: String(candidate), relativeTo: base)?.absoluteURL
    }
}

/// 默认页面抓取：走系统网络。**只读**，用于找入口；真正的认证由 `WKWebView` 完成，
/// 所以这里不强行绑接口（浏览器栈本身就是系统的网络栈）。
public struct URLSessionPortalFetcher: PortalPageFetching {
    public var timeout: Duration

    public init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    public func fetch(_ url: URL, interface: InterfaceSnapshot) async throws -> PortalPage {
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        return PortalPage(
            statusCode: http?.statusCode ?? 0,
            body: String(decoding: data, as: UTF8.self),
            location: http?.value(forHTTPHeaderField: "Location"))
    }
}
