import Foundation
import JLUGateCore
import JLUGateNet

/// 诊断包内容：接口快照 + 路由走向 + 脱敏配置 + 最近状态。
///
/// 一律**不含密码**，也不含登录摘要（摘要等价于密码，见 Fixtures/README）。
enum DiagnosticsReport {
    static func make(config: AppConfig,
                     engineState: AuthState,
                     interfaces: [InterfaceSnapshot]) -> String {
        var lines: [String] = []
        lines.append("JLU Gate 诊断信息  \(ISO8601DateFormatter().string(from: .now))")
        lines.append("")
        lines.append("状态：\(engineState.phase)")

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
        lines.append("账号：\(config.account.isEmpty ? "-" : config.account)")
        lines.append("链路：\(config.link)  通道：\(config.channel)")
        lines.append("服务器：\(config.server):\(config.serverPort)  本地端口：\(config.localPort)")
        if let profile = config.currentProfile {
            lines.append("静态 IP：\(profile.ip ?? "-")  掩码：\(profile.mask ?? "-")")
            lines.append("网关：\(profile.gateway ?? "-")  DNS：\(profile.dns.joined(separator: ","))")
            lines.append("登记 MAC：\(profile.registeredMAC ?? "-")")
        }
        lines.append("")
        let logTail = FileLogger.shared.tail(120)
        if !logTail.isEmpty {
            lines.append("")
            lines.append("== 最近日志 ==")
            lines.append(logTail)
        }

        lines.append("== 凭据存储 ==")
        lines.append(CredentialStore.backendDescription)

        lines.append("== 端口占用 ==")
        switch BSDChannel.diagnosePort(PacketLayout.localPort) {
        case .officialClient(let process, let pid):
            lines.append("61440 被官方客户端占用：\(process)（PID \(pid.map(String.init) ?? "?")）")
        case .other(let process):
            lines.append("61440 被其它进程占用：\(process)")
        case .unknown:
            lines.append("61440 当前没有看见占用者（或需要管理员权限才能看到）")
        }
        return lines.joined(separator: "\n")
    }
}
