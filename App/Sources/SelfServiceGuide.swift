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
                Text(isDynamicWiFi ? Copy.t("G01")
                                   : Copy.t("G02"))
                    .font(.system(size: titleSize, weight: .semibold))
                Spacer(minLength: 0)
            }

            Text(isDynamicWiFi
                 ? Copy.t("G03")
                   + Copy.t("G04")
                 : Copy.t("G05"))
                .font(.system(size: bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 文案变长（尤其英文）后，两个按钮并排会被截断：改成竖排，各占一行
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    NSWorkspace.shared.open(JLUAccessPolicy.selfServiceURL)
                } label: {
                    Label(Copy.t("G06"), systemImage: "safari")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(showSteps ? Copy.t("G07") : Copy.t("G08")) { showSteps.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if showSteps { steps }
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 展开后的步骤

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isDynamicWiFi {
                stepRow("1", Copy.t("G09")
                              + Copy.t("G10"))
                stepRow("2", Copy.t("G11"))
                stepRow("3", Copy.t("G12"))
            } else {
                stepRow("1", Copy.t("G13"))
                stepRow("2", Copy.t("G14"))
                stepRow("3", Copy.t("G15"))
                stepRow("4", Copy.t("G16"))
            }

            HStack(spacing: 10) {
                disclosureButton(Copy.t("G17"), isOpen: showPasswords) { showPasswords.toggle() }
                if !isDynamicWiFi {
                    disclosureButton(Copy.t("G18"), isOpen: showMACHint) { showMACHint.toggle() }
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
        Label(Copy.t("G19"),
              systemImage: "wifi")
            .font(.system(size: bodySize - 1))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var passwordList: some View {
        VStack(alignment: .leading, spacing: 5) {
            factRow(Copy.t("G20"),
                    Copy.t("G21"))
            factRow(Copy.t("G22"),
                    Copy.t("G23"))
            factRow(Copy.t("G24"),
                    Copy.t("G25"))
        }
        .padding(8)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 自己这台 Mac 上，两块网卡的 MAC 分别在哪看（按系统设置的路径写，照着点就行）
    private var macList: some View {
        VStack(alignment: .leading, spacing: 5) {
            factRow(Copy.t("G26"),
                    Copy.t("G27"))
            factRow("Wi-Fi",
                    Copy.t("G28"))
            Text(Copy.t("G29")
                 + Copy.t("G30"))
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
                Text(Copy.t("G31"))
                    .font(.system(size: bodySize, weight: .medium))
                Text(Copy.t("G32")
                     + Copy.t("G33")
                     + Copy.t("G34"))
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
    var text: String = Copy.t("G35")
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
            // 英文文案较长：两个入口竖排，避免按钮被截断
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    NSWorkspace.shared.open(JLUAccessPolicy.selfServiceURL)
                } label: {
                    Label(Copy.t("G36"), systemImage: "safari")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(expanded ? Copy.t("G07") : Copy.t("G37")) { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if expanded {
                SelfServiceGuideCard(compact: true)
            }
        }
    }
}
