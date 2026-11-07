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

public protocol EportalAuthenticating: Sendable {
    func login(entry: URL, account: String, password: String,
               clientIP: String?, clientMAC: String?) async -> EportalOutcome
}

/// 吉大 `JLU.WIFI` 的网页认证：**直接请求门户的登录接口**，不弹网页。
///
/// 学校门户是 Dr.COM 的两套/三代东西，按实测顺序试：
/// 1. **Dr.COM 4.0 网页登录**（吉大现在实际用的）：
///    `GET https://net.jlu.edu.cn/drcom/login?callback=dr1003&DDDDD=...&upass=...`
///    返回 JSONP：`result=1` 成功，`result=0` 失败（`msg` 是数字代码，`msga` 是原因）。
///    注意：这里必须用**域名**。801 的 ACSetting 会 302 到 `https://10.100.61.7:802`，
///    但证书是 `*.jlu.edu.cn`，直接连 IP 会在 TLS 校验上失败——旧实现就栽在这里，
///    于是永远"静默登录不支持"、只能回退到浏览器。
/// 2. **EPortal 4.x JSON 接口**：`https://<host>:802/eportal/portal/login`。
/// 3. **老版 Dr.COM WebLogin**：`http://<host>:801/eportal/?c=ACSetting&a=Login`
///    （表单字段 `DDDDD` / `upass`）。
///
/// 只有三套都明确"不认"时才返回 `.unsupported`，交给浏览器兜底。
public struct EportalClient: EportalAuthenticating {
    public var timeout: Duration

    public init(timeout: Duration = .seconds(8)) {
        self.timeout = timeout
    }

    /// 登录。`entry` 是门户入口（通常是 `http://net.jlu.edu.cn/` 或网关地址）。
    public func login(entry: URL, account: String, password: String,
                      clientIP: String?, clientMAC: String?) async -> EportalOutcome {
        guard entry.host != nil, !account.isEmpty, !password.isEmpty else { return .unsupported }

        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let user = Self.userAccount(account)

        // 1. Dr.COM 4.0 网页登录（吉大实测走这条）
        if let outcome = await postDrcomWebLogin(entry: entry, account: user, password: password,
                                                 session: session) {
            return outcome
        }

        // 2. 新版 EPortal：先从 801 的 ACSetting 确认 802 可用，但 base 始终用入口域名
        if let base = await resolveEportalBase(entry: entry, session: session) {
            let outcome = await postEPortal(base: base, account: user, password: password,
                                            clientIP: clientIP, clientMAC: clientMAC, session: session)
            if outcome != .unsupported { return outcome }
        }

        // 3. 老版 Dr.COM：801 上的 ACSetting 表单
        if let legacy = await postLegacyACSetting(entry: entry, account: user, password: password,
                                                   session: session) {
            return legacy
        }
        return .unsupported
    }

    /// 注销（用户主动下线时用）。
    public func logout(entry: URL, clientIP: String?) async {
        guard entry.host != nil else { return }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        guard let base = await resolveEportalBase(entry: entry, session: session) else { return }
        let url = base.appendingPathComponent("portal/logout")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "wlan_user_ip", value: clientIP ?? "")]
        guard let finalURL = components?.url else { return }
        _ = try? await data(for: finalURL, method: "GET", body: nil, session: session)
    }

    // MARK: 1. Dr.COM 4.0

    /// `GET /drcom/login?...`。返回 nil 表示"这个地址根本不是该接口"（继续试下一种）。
    func postDrcomWebLogin(entry: URL, account: String, password: String,
                           session: URLSession) async -> EportalOutcome? {
        let callback = "dr1003"
        for base in drcomLoginURLs(entry: entry) {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "callback", value: callback),
                URLQueryItem(name: "DDDDD", value: account),
                URLQueryItem(name: "upass", value: password),
                URLQueryItem(name: "0MKKey", value: "123456"),
                URLQueryItem(name: "R1", value: ""),
                URLQueryItem(name: "R2", value: ""),
                URLQueryItem(name: "R3", value: ""),
                URLQueryItem(name: "R6", value: "0"),
                URLQueryItem(name: "para", value: ""),
                URLQueryItem(name: "v6ip", value: ""),
                URLQueryItem(name: "terminal_type", value: "1"),
                URLQueryItem(name: "lang", value: "zh"),
                URLQueryItem(name: "v", value: String(Int.random(in: 500...10000))),
            ]
            guard let finalURL = components?.url,
                  let (data, response) = try? await data(for: finalURL, method: "GET",
                                                         body: nil, session: session),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                continue
            }
            let text = PortalTextCoding.decode(
                data, contentType: http.value(forHTTPHeaderField: "Content-Type"))
            if let json = Self.jsonObject(in: text) {
                return Self.outcome(from: json)
            }
            // 有些版本直接返回老式 HTML 成功/失败页
            let lowered = text.lowercased()
            if lowered.contains("dr.comwebloginid_3") { return .success }
            if lowered.contains("dr.comwebloginid_2") {
                return .failed("账号或密码不对，请重新输入")
            }
        }
        return nil
    }

    /// `/drcom/login` 的候选地址。
    ///
    /// - 域名入口：优先 `https`，再退回 `http`（吉大门户强制 https，但旧部署可能只开 http）。
    /// - IP 入口：直接走 `http`（`*.jlu.edu.cn` 证书不可能匹配 IP），并优先试学校域名。
    func drcomLoginURLs(entry: URL) -> [URL] {
        guard let host = entry.host, !host.isEmpty else { return [] }
        let isIP = Self.looksLikeIPAddress(host)
        var hosts: [String] = []
        if isIP, !Self.isLoopback(host) {
            // 门户入口是网关/本机 IP 时，学校真正的登录接口在域名上（证书也只签了域名）。
            hosts.append("net.jlu.edu.cn")
            hosts.append(host)
        } else {
            hosts.append(host)
        }

        var urls: [URL] = []
        for candidate in hosts {
            if Self.looksLikeIPAddress(candidate) {
                if let url = Self.loginURL(scheme: "http", host: candidate, entry: entry) {
                    urls.append(url)
                }
                continue
            }
            if let url = Self.loginURL(scheme: "https", host: candidate, entry: entry) {
                urls.append(url)
            }
            if let url = Self.loginURL(scheme: "http", host: candidate, entry: entry) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func loginURL(scheme: String, host: String, entry: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        // 入口带的 801 / 802 是 EPortal 端口，不是网页登录端口；丢掉。
        if let port = entry.port, ![80, 443, 801, 802].contains(port) {
            components.port = port
        }
        components.path = "/drcom/login"
        return components.url
    }

    // MARK: 2. EPortal 4.x

    /// 从 801 的 `ACSetting` 重定向确认 EPortal 在 802，但返回的 base **始终使用入口域名**。
    ///
    /// 为什么不用 Location 里的 `https://10.100.61.7:802`：证书 CN 是 `*.jlu.edu.cn`，
    /// 按 IP 连会在 TLS 校验时失败（真机实测），于是静默登录永远只能回退浏览器。
    public func resolveEportalBase(entry: URL) async -> URL? {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        return await resolveEportalBase(entry: entry, session: session)
    }

    private func resolveEportalBase(entry: URL, session: URLSession) async -> URL? {
        guard let host = entry.host, !Self.looksLikeIPAddress(host) else { return nil }
        // 先探一下 801，确认这台机器上 EPortal 真的在；探不到也没关系——
        // 直接按域名拼 802 仍然可能可用（例如 ACSetting 不响应但 EPortal 正常）。
        var probe = URLComponents()
        probe.scheme = "http"
        probe.host = host
        probe.port = 801
        probe.path = "/eportal/"
        probe.queryItems = [
            URLQueryItem(name: "c", value: "ACSetting"),
            URLQueryItem(name: "a", value: "Login"),
        ]
        if let url = probe.url,
           let (_, response) = try? await data(for: url, method: "GET", body: nil, session: session),
           let http = response as? HTTPURLResponse,
           http.value(forHTTPHeaderField: "Location") == nil {
            // 801 明确没有重定向：EPortal 可能不在这台 AC 上，交给下一套。
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = 802
        components.path = "/eportal/portal"
        return components.url
    }

    func postEPortal(base: URL, account: String, password: String,
                     clientIP: String?, clientMAC: String?,
                     session: URLSession? = nil) async -> EportalOutcome {
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
            URLQueryItem(name: "lang", value: "zh"),
        ]
        guard let finalURL = components?.url else { return .unsupported }
        let requestSession = session ?? makeSession()
        defer {
            if session == nil { requestSession.invalidateAndCancel() }
        }
        guard let (data, response) = try? await data(for: finalURL, method: "GET", body: nil,
                                                      session: requestSession) else {
            return .unsupported
        }
        let http = response as? HTTPURLResponse
        let text = PortalTextCoding.decode(
            data, contentType: http?.value(forHTTPHeaderField: "Content-Type"))
        return Self.parse(text)
    }

    // MARK: 3. 老版 ACSetting

    func postLegacyACSetting(entry: URL, account: String, password: String,
                             session: URLSession? = nil) async -> EportalOutcome? {
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
        let requestSession = session ?? makeSession()
        defer {
            if session == nil { requestSession.invalidateAndCancel() }
        }
        guard let (data, response) = try? await data(for: url, method: "POST", body: body,
                                                      session: requestSession),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else { return nil }
        let text = PortalTextCoding.decode(
            data, contentType: http.value(forHTTPHeaderField: "Content-Type"))
        return Self.parse(text)
    }

    // MARK: 解析

    /// 解析登录接口的返回（JSONP / JSON / 老版 HTML 都认）。
    public static func parse(_ text: String) -> EportalOutcome {
        if let json = jsonObject(in: text) {
            return outcome(from: json)
        }
        let lowered = text.lowercased()
        if lowered.contains("dr.comwebloginid_3") { return .success }
        if lowered.contains("dr.comwebloginid_2") {
            return .failed("账号或密码不对，请重新输入")
        }
        return .unsupported
    }

    /// 从 `callback({...})` / `{...}` 里取出 JSON 对象。
    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func outcome(from json: [String: Any]) -> EportalOutcome {
        let result = stringValue(json["result"])
        if result == "1" || result?.lowercased() == "ok" { return .success }

        let msg = stringValue(json["msg"])
        let msga = stringValue(json["msga"])
        let code = Int(msg ?? "")

        // 明确"接口不在"的情况：交给浏览器，而不是误报密码错。
        if let msg, msg.contains("没有配置接入服务器") { return .unsupported }

        if msg?.contains("在线") == true || msga?.contains("在线") == true {
            return .kicked(msg ?? msga ?? "账号已经在线")
        }

        // Dr.COM 的数字代码：2 = 该账号正在使用中（同一 IP 重新登录时也常报这个）。
        if code == 2 { return .kicked("终端或账号已经在线") }
        if let code {
            return .failed(failureMessage(code: code, msga: msga))
        }
        if let msg, !msg.isEmpty {
            return .failed(msg)
        }
        return .failed("门户拒绝了登录，但没有说明原因")
    }

    static func failureMessage(code: Int, msga: String?) -> String {
        let reason = msga?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowered = reason.lowercased()
        switch code {
        case 0, 1:
            if lowered.contains("userid error") || lowered.contains("auth error")
                || lowered.contains("password") || lowered.contains("passwd")
                || reason.contains("密码") || reason.contains("账号") {
                return "账号或密码不对，请重新输入"
            }
            if !reason.isEmpty { return "登录失败：\(reason)" }
            return "账号或密码不对，请重新输入"
        case 2:
            return "终端或账号已经在线"
        case 3:
            return "当前 IP 不在学校允许的地址范围内"
        case 4:
            return "网费余额不足，或已超出时长 / 流量限制"
        case 5:
            return "账号已停机或被暂停使用"
        case 6:
            return "认证系统繁忙，请稍后再试"
        case 7:
            return "已超出使用时长 / 流量限制"
        default:
            if reason.isEmpty { return "登录失败（服务器代码 \(code)）" }
            return "登录失败（服务器代码 \(code)：\(reason)）"
        }
    }

    /// 门户只认 `@` 前面的账号（选运营商后缀是另一个选项，这里没有）。
    static func userAccount(_ account: String) -> String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.lastIndex(of: "@"), at != trimmed.startIndex else { return trimmed }
        return String(trimmed[..<at])
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    static func formEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    static func looksLikeIPAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return String(value) == part || (part.count > 1 && part.first == "0")
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host.hasPrefix("127.") || host == "::1"
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(timeout.components.seconds)
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    private func data(for url: URL, method: String, body: String?,
                      session: URLSession) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
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
