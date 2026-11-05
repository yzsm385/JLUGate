import SwiftUI
import AppKit
import JLUGateCore

/// 「不会填」的时候给一条明路：校园网自助平台。
///
/// 新生卡住的通常不是按钮，而是**不知道自己的账号、密码、IP、MAC 是什么**。
/// 这里只做三件事：给入口、说清用哪一套密码、把步骤（和自己电脑的 MAC 在哪）摆在眼前。
///
/// 三个容易搞错的点，按真机反馈写死在这里：
/// - 「查询信息」里**没有 MAC**，登记 MAC 要从「变更 MAC」那个入口进；
/// - 自助平台用的是**校园卡号 + 6 位 V 卡密码**，和本 App 的统一账号密码不是一套，
///   所以这里**不复制账号**——复制过去反而会让人以为登录失败是密码错了；
/// - **JLU.WIFI 不需要任何静态参数**（动态地址 + 网页认证）；只有有线 / JLU.PC 才要填
///   IP / 掩码 / 网关 / 登记 MAC。
struct SelfServiceGuideCard: View {
    /// 面板里（380 宽）用紧凑字号；设置窗口里可以松一点
    var compact: Bool = false
    /// 当前选的接入方式；用来决定讲"静态参数"还是讲"网页认证"
    var link: String? = nil

    @State private var showSteps = false
    @State private var showPasswords = false
    @State private var showMACHint = false

    private var bodySize: CGFloat { compact ? 9 : 11 }
    private var titleSize: CGFloat { compact ? 10 : 12 }

    /// JLU.WIFI：本质是 HTTP 网页认证，地址由 DHCP 动态分配，不用填任何静态信息
    private var isDynamicWiFi: Bool { link == "jluWiFi" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: isDynamicWiFi ? "wifi" : "graduationcap")
                    .foregroundStyle(.blue)
                    .font(.system(size: titleSize))
                Text(isDynamicWiFi ? "JLU.WIFI：不用填 IP / MAC"
                                   : "不会填？去校园网自助平台查")
                    .font(.system(size: titleSize, weight: .semibold))
                Spacer(minLength: 0)
            }

            Text(isDynamicWiFi
                 ? "它是网页认证，地址由 DHCP 动态分配；用统一身份认证的账号密码在登录页登录。"
                   + "先确认 Wi-Fi 名字就是 JLU.WIFI（大写、带点），别在同名的可疑网络里输账号。"
                 : "固定 IP、网关在「查询信息」里；登记 MAC 在「变更 MAC」里。连不上也可能是网费欠了。")
                .font(.system(size: bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(JLUAccessPolicy.selfServiceURL)
                } label: {
                    Label("打开 ip.jlu.edu.cn/pay", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(showSteps ? "收起" : "看步骤") { showSteps.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if showSteps { steps }
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 展开后的步骤

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isDynamicWiFi {
                stepRow("1", "连上 JLU.WIFI（名字要一模一样），菜单栏点图标 →「登录」，"
                              + "在打开的网页里用统一身份认证的账号密码登录。")
                stepRow("2", "不用填 IP / 掩码 / 网关 / MAC——地址是动态分配的，网页认证只认账号。")
                stepRow("3", "自助平台只用来查网费、开户、看在线的设备。")
            } else {
                stepRow("1", "用校园卡号（录取通知书上那串，如 20220501324）＋ 6 位数字密码 ＋ 验证码登录。")
                stepRow("2", "点「查询信息」：IP、网关、DNS 都在这儿——这里没有 MAC。")
                stepRow("3", "登记 MAC 走另一个入口：点「变更 MAC」进去看/改。")
                stepRow("4", "列表里没有你的 IP：回主菜单点「网络开户」，开通后再回来查。")
            }

            HStack(spacing: 10) {
                disclosureButton("三种密码", isOpen: showPasswords) { showPasswords.toggle() }
                if !isDynamicWiFi {
                    disclosureButton("自己电脑的 MAC", isOpen: showMACHint) { showMACHint.toggle() }
                }
            }

            if showPasswords { passwordList }
            if showMACHint { macList }

            if !isDynamicWiFi { wifiNote }
            arrearsNote
        }
        .padding(.top, 2)
    }

    private func disclosureButton(_ title: String, isOpen: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                Text(title)
            }
            .font(.system(size: bodySize, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func stepRow(_ index: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(index)
                .font(.system(size: bodySize - 1, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(Circle().fill(Color.blue.opacity(0.8)))
            Text(text)
                .font(.system(size: bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 选成有线/JLU.PC 的人也可能其实是 Wi-Fi——顺手点一句，省得白填
    private var wifiNote: some View {
        Label("如果其实是连 JLU.WIFI：这些静态参数一个都不用填，那是动态地址的网页认证。",
              systemImage: "wifi")
            .font(.system(size: bodySize - 1))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var passwordList: some View {
        VStack(alignment: .leading, spacing: 5) {
            factRow("吉大 V 卡（校园卡）",
                    "账号 = 录取通知书号；密码 = 6 位数字。自助平台用的是这套。")
            factRow("吉大邮箱",
                    "独立的一套密码，只用来登邮箱；账号格式和统一账号一样。")
            factRow("统一身份认证",
                    "教务、VPN、还有本 App（含 JLU.WIFI 网页登录）用的都是这套。")
        }
        .padding(8)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 自己这台 Mac 上，两块网卡的 MAC 分别在哪看（按系统设置的路径写，照着点就行）
    private var macList: some View {
        VStack(alignment: .leading, spacing: 5) {
            factRow("有线网卡",
                    "系统设置 → 网络 → 点那根有线（USB 网卡也在这）→ 详细信息 → MAC 地址。")
            factRow("Wi-Fi",
                    "系统设置 → Wi-Fi → 点已加入的网（JLU.WIFI / JLU.PC）旁的「⋯」→ MAC。")
            Text("要的是这块网卡的物理地址。系统若开了「私有 Wi-Fi 地址 / 随机 MAC」，"
                 + "先关掉它，或在 App 里勾「用登记的 MAC 认证」。")
                .font(.system(size: bodySize - 1))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func factRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: bodySize, weight: .medium))
            Text(detail)
                .font(.system(size: bodySize - 1))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var arrearsNote: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "yensign.circle")
                .foregroundStyle(.orange)
                .font(.system(size: bodySize))
            VStack(alignment: .leading, spacing: 1) {
                Text("连不上，也可能是欠费")
                    .font(.system(size: bodySize, weight: .medium))
                Text("-10 元、0 元都还能上；到 -20 元就断（有线 / JLU.PC / JLU.WIFI 都一样）。"
                     + "充值档位只有 20 / 40 / 100，钱从校园卡余额扣——欠 20 时充 20 变成 0 不算数，"
                     + "要充 40 让余额变成 20 才能用。")
                    .font(.system(size: bodySize - 1))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

/// 向导里的一行版：只给入口和最关键的一句，不抢正文的位置。
struct SelfServiceHintRow: View {
    var text: String = "这些数字在自助平台「查询信息」里，用校园卡号 + 6 位 V 卡密码登录。"
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 10))
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(JLUAccessPolicy.selfServiceURL)
                } label: {
                    Label("打开自助平台", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(expanded ? "收起" : "新生看这里") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
            }
            if expanded {
                SelfServiceGuideCard(compact: true)
            }
        }
    }
}
