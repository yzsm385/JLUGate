import Foundation
import JLUGateCore
import JLUGateNet

/// 诊断包内容：接口快照 + 路由走向 + 脱敏配置 + 最近状态。
///
/// 一律**不含密码**，也不含登录摘要（摘要等价于密码，见 Fixtures/README）。
enum DiagnosticsReport {
    static func make(config: AppConfig,
                     engineState: AuthState,
                     interfaces: [InterfaceSnapshot],
                     portalPageCapture: String? = nil) -> String {
        var lines: [String] = []
        lines.append("JLU Gate 诊断信息  \(ISO8601DateFormatter().string(from: .now))")
        lines.append("版本：\(BuildInfo.version)（build \(BuildInfo.build)）  "
                     + "形态：\(AppIdentity.isInstalled ? "正式" : "便携")\(BuildInfo.isCompatBuild ? " / 兼容版" : "")")
        lines.append("系统：\(ProcessInfo.processInfo.operatingSystemVersionString)  "
                     + "架构：\(architecture())")
        lines.append("")
        lines.append("状态：\(engineState.phase)")
        lines.append("")
        lines.append("== 连接 ==")
        lines.append("链路偏好：\(config.link)  通道：\(config.channel)"
                     + "  保活间隔：\(config.keepAlive.interval)s  容忍：\(config.keepAlive.missTolerance)")
        lines.append("上次成功登录：\(config.lastSuccessfulLogin ?? "-")")
        lines.append("保活日志字段：round=子类型  seq=请求/应答共用自增序号  "
                     + "session=服务器会话  mirror=服务器上次镜像")

        let provider = SystemInterfaceProvider()
        lines.append("")
        lines.append("== 物理接口 ==")
        for item in interfaces {
            let method = provider.configMethod(of: item.name) ?? "?"
            lines.append("""
            \(item.name)  ifindex=\(item.index)  ipv4=\(item.ipv4 ?? "-")  \
            mac=\(item.mac ?? "-")  无线=\(item.isWireless ? "是" : "否")  \
            linkLocal=\(item.linkLocalIPv4 ?? "-")  ConfigMethod=\(method)
            """)
        }
        if interfaces.isEmpty {
            lines.append("(没有物理接口)")
        }

        lines.append("")
        lines.append("== 路由 ==")
        if let server = IPv4Address(config.server), let route = provider.route(to: server) {
            lines.append("route get \(config.server)：出口 \(route.interface ?? "?")，网关 \(route.gateway ?? "-")")
            lines.append(route.isTunnel ? "出口是虚拟接口：代理可能吞掉认证包" : "出口是物理接口")
        } else {
            lines.append("route get \(config.server) 失败")
        }
        lines.append("默认网关：\(provider.defaultGateway() ?? "-")")

        lines.append("")
        lines.append("== 配置（脱敏） ==")
        lines.append("账号：\(config.account.isEmpty ? "-" : Redact.account(config.account))")
        if !config.studentID.isEmpty {
            lines.append("学号：\(Redact.studentID(config.studentID))")
        }
        lines.append("链路：\(config.link)  通道：\(config.channel)")
        lines.append("服务器：\(config.server):\(config.serverPort)  本地端口：\(config.localPort)")
        if let profile = config.currentProfile {
            lines.append("静态 IP：\(profile.ip ?? "-")  掩码：\(profile.mask ?? "-")")
            lines.append("网关：\(profile.gateway ?? "-")  DNS：\(profile.dns.joined(separator: ","))")
            lines.append("登记 MAC：\(profile.registeredMAC.map(Redact.mac) ?? "-")")
        }
        lines.append("")
        let logTail = FileLogger.shared.tail(400)
        if !logTail.isEmpty {
            lines.append("")
            lines.append("== 最近日志 ==")
            lines.append(logTail)
        }

        if let portalPageCapture {
            lines.append("")
            lines.append(portalPageCapture)
        }

        lines.append("== 凭据存储 ==")
        lines.append(CredentialStore.backendDescription)

        lines.append("== 端口占用 ==")
        switch BSDChannel.diagnosePortExcludingSelf(PacketLayout.localPort) {
        case .officialClient(let process, let pid):
            lines.append("61440 被官方客户端占用：\(process)（PID \(pid.map(String.init) ?? "?")）")
        case .other(let process):
            lines.append("61440 被其它进程占用：\(process)")
        case .appItself:
            lines.append("61440 由 JLU Gate 自己占用（认证通道，正常）")
        case .unknown:
            lines.append("61440 当前没有看见占用者（或需要管理员权限才能看到）")
        }
        return lines.joined(separator: "\n")
    }

    static func portalPageSummary(requestedURL: URL, page: PortalPage) -> String {
        let responseURL = page.responseURL ?? requestedURL
        var lines = [
            "请求：\(safeURL(requestedURL))",
            "最终 URL：\(safeURL(responseURL))",
            "HTTP：\(page.statusCode)",
            "Content-Type：\(page.contentType ?? "-")",
            "页面字符数：\(page.body.count)",
        ]
        if let title = firstCapture(#"<title\b[^>]*>(.*?)</title>"#, in: page.body) {
            lines.append("标题：\(plainText(title))")
        } else {
            lines.append("标题：未找到")
        }

        let forms = tags(#"<form\b[^>]*>"#, in: page.body)
        lines.append("表单：\(forms.isEmpty ? "未找到" : "\(forms.count) 个")")
        for (index, form) in forms.prefix(10).enumerated() {
            let action = attribute("action", in: form).flatMap {
                URL(string: $0, relativeTo: responseURL)?.absoluteURL
            }
            lines.append("  form[\(index)] method=\(attribute("method", in: form) ?? "-")"
                         + " action=\(action.map(safeURL) ?? "-")")
        }

        let controls = tags(#"<(?:input|select|textarea|button)\b[^>]*>"#, in: page.body)
        lines.append("表单控件：\(controls.count) 个（只列 name/type/id，不记录输入值）")
        for control in controls.prefix(30) {
            let name = attribute("name", in: control) ?? "-"
            let type = attribute("type", in: control) ?? "-"
            let id = attribute("id", in: control) ?? "-"
            lines.append("  name=\(name) type=\(type) id=\(id)")
        }

        let scripts = scriptURLs(in: page, requestedURL: requestedURL)
            .map(safeURL)
        lines.append("外链脚本：\(scripts.isEmpty ? "无" : scripts.prefix(20).joined(separator: ", "))")

        let markers = ["Dr.COMWebLoginID_1", "Dr.COMWebLoginID_2", "Dr.COMWebLoginID_3",
                       "authloginIP", "authloginport", "authloginpath", "authloginparam",
                       "eportal", "DDDDD", "upass"]
            .filter { page.body.localizedCaseInsensitiveContains($0) }
        lines.append("认证标记：\(markers.isEmpty ? "未识别" : markers.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    static func scriptURLs(in page: PortalPage, requestedURL: URL) -> [URL] {
        let baseURL = page.responseURL ?? requestedURL
        return tags(#"<script\b[^>]*>"#, in: page.body)
            .compactMap { attribute("src", in: $0) }
            .compactMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
    }

    static func safeURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "(invalid URL)"
        }
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { URLQueryItem(name: $0.name, value: "[redacted]") }
        }
        components.user = nil
        components.password = nil
        return components.string ?? url.host ?? "(invalid URL)"
    }

    private static func tags(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let source = text as NSString
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
              match.numberOfRanges > 1 else { return nil }
        return source.substring(with: match.range(at: 1))
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)\b\#(escapedName)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = tag as NSString
        guard let match = expression.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)) else {
            return nil
        }
        for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
            return source.substring(with: match.range(at: index))
        }
        return nil
    }

    private static func architecture() -> String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
