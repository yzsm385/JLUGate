import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 静默网页认证的结果。
public enum EportalOutcome: Sendable, Equatable {
    /// 登录接口说成功了（还需要 204 探针确认）
    case success
    /// 账号已经在别处在线 / 被新设备挤掉
    case kicked(String)
    /// 其他失败（密码错、接口不认等）
    case failed(String)
    /// 这个门户不支持静默登录，只能走浏览器
    case unsupported
}

/// 吉大 `JLU.WIFI` 的网页认证：**直接 POST 门户的登录接口**，不弹网页。
///
/// 学校的门户有两套（都是 Dr.COM 的）：
/// 1. 新版 EPortal：`https://<AC>:802/eportal/portal/login?callback=dr1003&...`
///    （账号写成 `,0,<账号>`，参数见 `JLU.WIFI` 抓包）；
/// 2. 老版 Dr.COM WebLogin：`http://<host>:801/eportal/?c=ACSetting&a=Login`，
///    表单字段 `DDDDD` / `upass`。
///
/// 两套都试，哪套返回成功就用哪套；都不行就交回浏览器（`PortalEngine` 的兜底）。
public struct EportalClient: Sendable {
    public var timeout: Duration

    public init(timeout: Duration = .seconds(8)) {
        self.timeout = timeout
    }

    /// 登录。`entry` 是门户入口（通常是 `http://net.jlu.edu.cn/` 或网关地址）。
    public func login(entry: URL, account: String, password: String,
                      clientIP: String?, clientMAC: String?) async -> EportalOutcome {
        let host = entry.host ?? ""
        guard !host.isEmpty, !account.isEmpty else { return .unsupported }

        // 新版 EPortal：先从 801 的 ACSetting 拿真实 AC 地址（会 302 到 https://AC:802）
        if let base = await resolveEportalBase(entry: entry) {
            let outcome = await postEPortal(base: base, account: account, password: password,
                                            clientIP: clientIP, clientMAC: clientMAC)
            if outcome != .unsupported { return outcome }
        }

        // 老版 Dr.COM：801 上的 ACSetting 表单
        if let legacy = await postLegacyACSetting(entry: entry, account: account, password: password) {
            return legacy
        }
        return .unsupported
    }

    /// 注销（用户主动下线时用）。
    public func logout(entry: URL, clientIP: String?) async {
        guard let host = entry.host, let base = await resolveEportalBase(entry: entry) else { return }
        let url = base.appendingPathComponent("portal/logout")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "wlan_user_ip", value: clientIP ?? "")]
        guard let finalURL = components?.url else { return }
        _ = try? await data(for: finalURL, method: "GET", body: nil)
        _ = host
    }

    // MARK: 解析

    /// 从 801 的 `ACSetting` 重定向里取出真实 EPortal 根地址（`https://10.100.61.7:802/eportal/`）。
    public func resolveEportalBase(entry: URL) async -> URL? {
        guard let host = entry.host else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = 801
        components.path = "/eportal/"
        components.queryItems = [
            URLQueryItem(name: "c", value: "ACSetting"),
            URLQueryItem(name: "a", value: "Login"),
        ]
        guard let probe = components.url else { return nil }
        guard let (_, response) = try? await data(for: probe, method: "GET", body: nil) else { return nil }
        guard let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              var target = URL(string: location) else { return nil }
        // Location 形如 https://10.100.61.7:802/eportal/?c=ACSetting&a=Login
        // 统一收敛到 `.../eportal/portal`（后面拼 login）
        if let range = target.absoluteString.range(of: "/eportal/") {
            let prefix = String(target.absoluteString[..<range.upperBound])
            return URL(string: prefix + "portal")
        }
        if let range = target.absoluteString.range(of: "/eportal") {
            let prefix = String(target.absoluteString[..<range.upperBound])
            return URL(string: prefix + "/portal")
        }
        return target
    }

    func postEPortal(base: URL, account: String, password: String,
                     clientIP: String?, clientMAC: String?) async -> EportalOutcome {
        // base 是 .../eportal/portal；拼成 .../eportal/portal/login
        var url = base
        if url.lastPathComponent != "login" { url.appendPathComponent("login") }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "callback", value: "dr1003"),
            URLQueryItem(name: "login_method", value: "1"),
            URLQueryItem(name: "user_account", value: ",0,\(account)"),
            URLQueryItem(name: "user_password", value: password),
            URLQueryItem(name: "wlan_user_ip", value: clientIP ?? ""),
            URLQueryItem(name: "wlan_user_mac", value: (clientMAC ?? "").replacingOccurrences(of: ":", with: "")),
            URLQueryItem(name: "wlan_ac_ip", value: ""),
            URLQueryItem(name: "wlan_ac_name", value: ""),
            URLQueryItem(name: "jsVersion", value: "4.1"),
            URLQueryItem(name: "terminal_type", value: "1"),
            URLQueryItem(name: "lang", value: "zh-cn"),
        ]
        guard let finalURL = components?.url else { return .unsupported }
        guard let (data, _) = try? await data(for: finalURL, method: "GET", body: nil) else {
            return .unsupported
        }
        return Self.parse(String(decoding: data, as: UTF8.self))
    }

    func postLegacyACSetting(entry: URL, account: String, password: String) async -> EportalOutcome? {
        guard let host = entry.host else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = 801
        components.path = "/eportal/"
        components.queryItems = [
            URLQueryItem(name: "c", value: "ACSetting"),
            URLQueryItem(name: "a", value: "Login"),
            URLQueryItem(name: "url", value: "drappall"),
        ]
        guard let url = components.url else { return nil }
        let body = "DDDDD=\(Self.formEncode(account))&upass=\(Self.formEncode(password))&0MKKey=%B5%C7%C2%BC"
        guard let (data, _) = try? await data(for: url, method: "POST", body: body) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("Dr.COMWebLoginID_3") { return .success }
        if text.contains("Dr.COMWebLoginID_2") { return .failed("账号或密码不对") }
        return Self.parse(text)
    }

    /// 解析登录接口的返回（JSONP / JSON / 老版 HTML 都认）。
    public static func parse(_ text: String) -> EportalOutcome {
        let lowered = text.lowercased()
        if lowered.contains("\"result\":1") || lowered.contains("\"result\":\"1\"") { return .success }
        if lowered.contains("dr.comwebloginid_3") { return .success }
        if lowered.contains("dr.comwebloginid_2") { return .failed("账号或密码不对") }

        if let message = message(in: text) {
            if message.contains("已经在线") || message.contains("已在线")
                || message.contains("被踢") || message.contains("挤下")
                || message.contains("在线设备") {
                return .kicked(message)
            }
            if message.contains("没有配置接入服务器") { return .unsupported }
            return .failed(message)
        }
        if lowered.contains("\"result\":0") { return .failed("门户拒绝了登录") }
        return .unsupported
    }

    static func message(in text: String) -> String? {
        guard let range = text.range(of: "\"msg\"") else { return nil }
        let tail = text[range.upperBound...]
        guard let colon = tail.firstIndex(of: ":") else { return nil }
        let after = tail[tail.index(after: colon)...]
        guard let quote = after.firstIndex(of: "\"") else { return nil }
        let value = after[after.index(after: quote)...]
        guard let closing = value.firstIndex(of: "\"") else { return nil }
        return String(value[..<closing])
    }

    static func formEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    private func data(for url: URL, method: String, body: String?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }
}

/// 不自动跟随重定向：801 → 802 的那一跳要自己读 Location。
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// 静默登录需要的凭据（只在内存里活一次，不落盘）。
public struct PortalCredentials: Sendable {
    public var account: String
    public var password: String
    public var clientMAC: String?

    public init(account: String, password: String, clientMAC: String? = nil) {
        self.account = account
        self.password = password
        self.clientMAC = clientMAC
    }
}
