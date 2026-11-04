import Foundation

/// 全部可预期的失败，**一条一句话**，不许笼统"登录失败"（CHECKLIST §8）。
public enum DrcomError: Error, Sendable, Equatable {
    // MARK: 协议 / 报文

    /// 报文长度或偏移不合法（编解码层唯一的兜底错误）。
    case malformed(String)
    /// `(type, subtype, length)` 三元组不在帧表里，记为"不认识的包"，不崩。
    case unexpectedPacket(type: UInt8, subtype: UInt8, length: Int)
    /// 定长字段超长（账号 > 31 字节、主机名 ≥ 26 字节等）。
    case fieldTooLong(field: String, max: Int)
    /// 服务器明确拒绝，`reason` 为服务器原文，直接展示（`ldap auth error` 等）。
    case rejected(reason: String)

    // MARK: 环境（"先证伪环境，再怀疑凭据"）

    /// 当前网卡 MAC 与档案里登记的 MAC 不一致。
    case macMismatch(expected: String?, actual: String?)
    /// 接口在，但没有 IPv4（新插 USB 网卡默认就是这种状态）。
    case interfaceHasNoIPv4(interface: String)
    /// 网卡消失（拔线 / 拔 USB 网卡）。
    case adapterUnplugged(interface: String)
    /// `ipconfig getsummary` 显示，接入方式仍是 DHCP —— 静态认证必然失败。
    case dhcpAssigned(interface: String)
    /// 系统实际配置与用户档案不符（IP / 掩码 / 网关 / DNS）。
    case staticConfigMismatch(field: String, expected: String, actual: String)
    /// 网关无回应（连 challenge 都收不到）。
    case gatewayUnreachable(host: String)
    /// `route get 10.100.61.3` 的出口是虚拟接口，报文会被代理吞掉。
    case capturedByTunnel(interface: String)
    /// 61440 被官方客户端占用（`drcomauth` / `DrClientNS`）。
    case officialClientRunning(process: String, pid: Int32?)
    /// 61440 被其它进程占用。
    case localPortInUse(port: UInt16, process: String?)

    // MARK: 服务器侧账号状态

    /// 账号在别处登录。
    case accountInUse(reason: String)
    /// 同一 MAC 被另一台设备占用。
    case macInUse(reason: String)
    /// 服务器认为这个 MAC 不属于该账号（登记的是另一块网卡）。
    case macRejected(reason: String)

    // MARK: 链路选择

    /// 探针判定当前网络不是校园网（challenge 无回执、204 探针也不通）。
    case notCampusNetwork(detail: String)
    /// 该链路当前版本还没实现（例如 `JLU.WIFI` 的网页登录）。
    case unsupportedLink(String)

    // MARK: 传输

    case timeout(stage: String)
    case channelFailure(String)
    /// 任务被取消（切换 epoch / 休眠）。
    case cancelled

    /// 给用户看的一句话。**`rejected` / `accountInUse` / `macInUse` 原样返回服务器串**。
    public var userMessage: String {
        switch self {
        case .malformed(let detail):
            return "报文格式错误（\(detail)）"
        case .unexpectedPacket(let type, let subtype, let length):
            return "收到未知报文：类型 0x\(hex(type)) 子类型 0x\(hex(subtype))，长度 \(length)"
        case .fieldTooLong(let field, let max):
            return "\(field) 太长，最多 \(max) 字节"
        case .rejected(let reason):
            return reason
        case .macMismatch(let expected, let actual):
            let want = expected ?? "未登记"
            let got = actual ?? "无"
            return "网卡 MAC 不匹配：档案登记 \(want)，当前接口 \(got)。换 USB 网卡后需要去学校平台登记新 MAC。"
        case .interfaceHasNoIPv4(let name):
            return "接口 \(name) 没有 IPv4 地址。请到系统设置给这块网卡配上静态地址（不能是 DHCP）。"
        case .adapterUnplugged(let name):
            return "网卡 \(name) 已断开（拔线或拔卡）。插回后会自动重连。"
        case .dhcpAssigned(let name):
            return "接口 \(name) 仍在使用 DHCP，未改成手动配置。静态认证不接受 DHCP 地址。"
        case .staticConfigMismatch(let field, let expected, let actual):
            return "\(field) 与档案不一致：应为 \(expected)，当前 \(actual)"
        case .gatewayUnreachable(let host):
            return "认证服务器 \(host) 无响应。请确认网线、静态 IP 与网关。"
        case .capturedByTunnel(let name):
            return "检测到代理接管了校园网段（出口 \(name)）。请在代理规则里把 10.0.0.0/8 设为直连，或关闭全局路由。"
        case .officialClientRunning(let process, let pid):
            let pidText = pid.map { "（PID \($0)）" } ?? ""
            return "官方 Dr.Com 客户端\(pidText)正握着认证通道（它先占了本地 61440）——通常说明它已经在替你上网。"
                + "想让 JLU Gate 接管，先在它里面退出登录；若端口仍被占，关掉它的后台进程 DrClientNS。"
        case .localPortInUse(let port, let process):
            let who = process.map { "（\($0)）" } ?? ""
            return "认证要用的那个「联系电话」（本地 61440）被别的程序先占了\(who)。"
                + "如果是官方 Dr.Com 客户端，先退出它就对了。"
        case .accountInUse(let reason):
            return reason
        case .macInUse(let reason), .macRejected(let reason):
            return reason
        case .notCampusNetwork(let detail):
            return "当前网络不是校园网（\(detail)）"
        case .unsupportedLink(let detail):
            return "该接入方式尚未支持：\(detail)"
        case .timeout(let stage):
            return "等待服务器回应超时（\(stage)）"
        case .channelFailure(let detail):
            return "网络通道异常：\(detail)"
        case .cancelled:
            return "已取消"
        }
    }

    /// 是否值得自动重试。账号冲突 / DHCP / MAC 不匹配这类必须等用户动作。
    /// 服务器是否在说"账号或密码不对"（LDAP 验证失败）。
    /// 这类错误重试多少次都一样，必须请用户重新输入密码。
    public var isCredentialRejection: Bool {
        guard case .rejected(let reason) = self else { return false }
        let lowered = reason.lowercased()
        return lowered.contains("ldap") || lowered.contains("auth")
            || lowered.contains("password") || reason.contains("密码")
            || reason.contains("账号不存在")
    }

    public var isRetryable: Bool {
        switch self {
        case .unexpectedPacket, .accountInUse, .macInUse, .macRejected, .dhcpAssigned,
             .staticConfigMismatch, .capturedByTunnel, .officialClientRunning,
             .localPortInUse, .macMismatch, .cancelled, .rejected:
            return false
        case .malformed, .fieldTooLong, .interfaceHasNoIPv4, .adapterUnplugged,
             .gatewayUnreachable, .timeout, .channelFailure, .notCampusNetwork:
            return true
        case .unsupportedLink:
            return false
        }
    }

    /// 是否应当"停下来等网络变化"，而不是按退避空转重试。
    ///
    /// 拔网线 / 网卡没地址这两种情况，插回去就是几秒钟的事；按 8 次退避空转
    /// 除了刷日志没有任何意义（PLAN §6.3）。真正的恢复由 `PathMonitor` 触发。
    public var awaitsPathChange: Bool {
        switch self {
        case .adapterUnplugged, .interfaceHasNoIPv4: true
        default: false
        }
    }

    /// 重连时是否需要"等用户"（进 `failed` 而不是 `reconnecting`）。
    public var requiresUserAction: Bool {
        switch self {
        case .accountInUse, .macInUse, .macRejected, .macMismatch, .dhcpAssigned,
             .staticConfigMismatch, .capturedByTunnel, .localPortInUse, .unsupportedLink:
            return true
        default:
            return false
        }
    }

    /// 服务器拒绝原因的分类。原因串**原样保留**，只用来决定要不要自动重试。
    public static func classifyRejection(_ reason: String) -> DrcomError {
        let lowered = reason.lowercased()
        let mentionsMAC = lowered.contains("mac")

        // 先分"占用"还是"不符"：这两件事对用户的含义完全不同
        let inUseWords = ["占用", "已被", "in use", "occupied", "another device"]
        let mismatchWords = ["不符", "不一致", "不匹配", "错误", "mismatch", "not match",
                             "invalid", "未登记", "未绑定", "非法"]

        if mentionsMAC {
            if mismatchWords.contains(where: lowered.contains) {
                return .macRejected(reason: reason)
            }
            if inUseWords.contains(where: lowered.contains) || reason.contains("该MAC") {
                return .macInUse(reason: reason)
            }
            return .macRejected(reason: reason)   // 没写清楚就按"MAC 有问题"处理，别退化成笼统拒绝
        }
        if reason.contains("别处") || reason.contains("已在") || lowered.contains("online")
            || lowered.contains("in use") {
            return .accountInUse(reason: reason)
        }
        return .rejected(reason: reason)
    }

    private func hex(_ value: UInt8) -> String {
        String(format: "%02x", value)
    }
}
