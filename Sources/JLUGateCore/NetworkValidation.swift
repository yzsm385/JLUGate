import Foundation

/// 静态网络参数的本地校验（PLAN §9.1 的"输入即验"）。
///
/// 这些值只能人工照抄，抄错的概率比想象中高得多：掩码写成 255.255.255.5、
/// 网关和 IP 不在同一网段（最常见的错），都会导致"能配上但上不了网"，
/// 而服务器只会回一句含糊的失败。
public enum NetworkValidation {
    public enum Issue: Sendable, Equatable {
        case invalidIPv4(field: String)
        /// 掩码必须是连续的 1（`255.255.255.0` 合法；把 0 与 1 交错写出来的掩码非法）
        case invalidMask(String)
        case gatewayNotInSubnet(ip: String, mask: String, gateway: String)
        case gatewayEqualsHost(String)
        case invalidMAC(String)

        public var message: String {
            switch self {
            case .invalidIPv4(let field): Copy.f("B201", field)
            case .invalidMask(let mask): Copy.f("B202", mask)
            case .gatewayNotInSubnet(let ip, let mask, let gateway):
                Copy.f("B203", gateway, ip, mask)
            case .gatewayEqualsHost(let gateway): Copy.f("B204", gateway)
            case .invalidMAC(let mac): Copy.f("B205", mac)
            }
        }
    }

    /// 把界面里的写法（可能带中间点 `·`）转成标准点分十进制再落盘。
    /// UI 用中间点只是显示习惯，配置里统一存 `203.0.113.11`，避免以后任何字符串比较出错。
    public static func canonical(_ text: String) -> String {
        IPv4Address(text)?.description ?? text
    }

    public static func canonicalMAC(_ text: String) -> String {
        MACAddress(text)?.description ?? text
    }

    /// 校验一份静态参数；返回全部问题（一次列全，别让用户试三遍）。
    public static func issues(ip: String?, mask: String?, gateway: String?, mac: String?) -> [Issue] {
        var issues: [Issue] = []

        var ipValue: IPv4Address?
        if let ip, !ip.isEmpty {
            if let parsed = IPv4Address(ip) { ipValue = parsed } else { issues.append(.invalidIPv4(field: "IP")) }
        }

        var maskValue: IPv4Address?
        if let mask, !mask.isEmpty {
            if let parsed = IPv4Address(mask), isContiguousMask(parsed) {
                maskValue = parsed
            } else {
                issues.append(.invalidMask(mask))
            }
        }

        var gatewayValue: IPv4Address?
        if let gateway, !gateway.isEmpty {
            if let parsed = IPv4Address(gateway) { gatewayValue = parsed } else { issues.append(.invalidIPv4(field: Copy.t("B206"))) }
        }

        if let mac, !mac.isEmpty, MACAddress(mac) == nil {
            issues.append(.invalidMAC(mac))
        }

        if let ipValue, let maskValue, let gatewayValue {
            if ipValue == gatewayValue {
                issues.append(.gatewayEqualsHost(gatewayValue.description))
            } else if !sameSubnet(ipValue, gatewayValue, mask: maskValue) {
                issues.append(.gatewayNotInSubnet(ip: ipValue.description,
                                                  mask: maskValue.description,
                                                  gateway: gatewayValue.description))
            }
        }
        return issues
    }

    /// 掩码必须形如 111…000（不允许 0/1 交错）。
    public static func isContiguousMask(_ mask: IPv4Address) -> Bool {
        let value = mask.uint32BE
        guard value != 0 else { return false }        // 0.0.0.0 不是掩码
        let inverted = ~value
        // 取反后必须是最低位连续的 1：inverted & (inverted + 1) == 0
        return (inverted & (inverted &+ 1)) == 0
    }

    public static func sameSubnet(_ a: IPv4Address, _ b: IPv4Address, mask: IPv4Address) -> Bool {
        let maskValue = mask.uint32BE
        return (a.uint32BE & maskValue) == (b.uint32BE & maskValue)
    }
}

/// 网络参数卡片：换机/重装时"复制一段文本 → 粘贴还原"（PLAN §9 / M4 验收）。
///
/// **不含密码**，也不含任何服务器端信息；只承载学校分配的网络参数。
public enum NetworkCard {
    public static func format(account: String,
                              profile: (ip: String?, mask: String?, gateway: String?,
                                        dns: [String], mac: String?),
                              link: String,
                              server: String,
                              serverPort: Int) -> String {
        """
        # JLU Gate 网络参数卡
        账号: \(account)
        链路: \(link)
        IP: \(profile.ip ?? "")
        掩码: \(profile.mask ?? "")
        网关: \(profile.gateway ?? "")
        DNS: \(profile.dns.joined(separator: ","))
        登记MAC: \(profile.mac ?? "")
        服务器: \(server):\(serverPort)
        """
    }

    public struct Parsed: Sendable, Equatable {
        public var account: String?
        public var link: String?
        public var ip: String?
        public var mask: String?
        public var gateway: String?
        public var dns: [String]
        public var mac: String?
        public var server: String?
        public var serverPort: Int?
    }

    /// 宽松解析：只认 `键: 值` 行，多余内容和 `#` 注释都忽略。
    public static func parse(_ text: String) -> Parsed {
        var parsed = Parsed(account: nil, link: nil, ip: nil, mask: nil, gateway: nil,
                            dns: [], mac: nil, server: nil, serverPort: nil)
        for rawLine in text.split(separator: "\n") {
            // 用户常常是从微信/备忘录里粘过来的，全角冒号和全角空格都得认
            let normalized = rawLine
                .replacingOccurrences(of: "：", with: ":")
                .replacingOccurrences(of: "\u{3000}", with: " ")
            let line = normalized.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "账号", "account": parsed.account = value.isEmpty ? nil : value
            case "链路", "link": parsed.link = value.isEmpty ? nil : value
            case "ip": parsed.ip = value.isEmpty ? nil : value
            case "掩码", "mask", "子网掩码": parsed.mask = value.isEmpty ? nil : value
            case "网关", "gateway": parsed.gateway = value.isEmpty ? nil : value
            case "dns":
                parsed.dns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "登记mac", "mac", "mac地址": parsed.mac = value.isEmpty ? nil : value
            case "服务器", "server":
                let parts = value.split(separator: ":")
                parsed.server = parts.first.map(String.init)
                parsed.serverPort = parts.count > 1 ? Int(parts[1]) : nil
            default:
                continue
            }
        }
        return parsed
    }
}
