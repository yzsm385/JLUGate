import SwiftUI
import AppKit
import JLUGateCore

/// 「站点合集」：把吉大常用入口收进来，点一下就能开；能预填的顺手把账号复制好。
struct SitesPanel: View {
    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var copiedHint: String?
    @State private var collegeQuery = ""
    @State private var showAllColleges = false

    private var grouped: [(category: JLUSite.Category, sites: [JLUSite])] {
        JLUSite.Category.allCases.compactMap { category in
            let sites = JLUSiteDirectory.sites(in: category).filter { site in
                query.isEmpty
                    || site.title.localizedCaseInsensitiveContains(query)
                    || site.host.localizedCaseInsensitiveContains(query)
                    || site.note.localizedCaseInsensitiveContains(query)
            }
            return sites.isEmpty ? nil : (category, sites)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "link")
                    Text("吉大常用站点").font(.headline)
                    Spacer()
                }

                TextField("搜站点、域名或用途…", text: $query)
                    .textFieldStyle(.roundedBorder)

                Text("标注「仅校内」的站点在校外打不开，先连 WebVPN；「需 VPN」表示页面能开、里面的资源要校园网。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                myCollegeCard

                ForEach(grouped, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.category.rawValue)
                            .font(.caption).bold()
                            .foregroundStyle(.secondary)
                        ForEach(group.sites) { site in
                            row(site)
                        }
                    }
                }

                if grouped.isEmpty {
                    Text("没有匹配的站点").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .overlay(alignment: .bottom) {
            if let copiedHint {
                Text(copiedHint)
                    .font(.caption2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 我的学院

    @ViewBuilder
    private var myCollegeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("我的学院").font(.caption).bold()
            if let college = model.myCollege {
                HStack(spacing: 6) {
                    Text(college.name).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("打开官网") {
                        if let url = college.url { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("换一个") { model.clearMyCollege() }
                        .buttonStyle(.link).font(.system(size: 10))
                }
                Text(college.host).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("填学号，选一次学院，之后自动认出来（只存在本机）")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if model.myCollege == nil {
                HStack(spacing: 6) {
                    TextField("学号", text: Binding(
                        get: { model.studentID },
                        set: { model.updateStudentID($0) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField("搜学院名或域名", text: $collegeQuery)
                        .textFieldStyle(.roundedBorder)
                }
                let matches = CollegeDirectory.search(collegeQuery)
                let shown = showAllColleges ? matches : Array(matches.prefix(6))
                Text(collegeCountText(matches.count))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                ForEach(shown) { college in
                    Button {
                        model.setMyCollege(college)
                    } label: {
                        HStack {
                            Text(college.name).font(.system(size: 11))
                            Spacer()
                            Text(college.host).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if matches.count > 6, !showAllColleges {
                    Button("展开全部 \(matches.count) 个学院") { showAllColleges = true }
                        .buttonStyle(.link).font(.system(size: 10))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 明确告诉用户"一共有多少个"，避免只看到 6 个以为就这些
    private func collegeCountText(_ total: Int) -> String {
        let all = CollegeDirectory.all.count
        if total == all { return "一共 \(all) 个学院" }
        if total > 6, !showAllColleges {
            return "匹配 \(total) 个，先显示前 6 个；继续输入可以缩小范围，或点下面展开"
        }
        return "匹配 \(total) 个"
    }

    private func row(_ site: JLUSite) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(site.title).font(.system(size: 12, weight: .medium))
                badge(site.access)
                Spacer()
                Button("打开") { open(site) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text("\(site.host) · \(site.note)")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if site.supportsCredentialPrefill {
                HStack(spacing: 6) {
                    Button("复制账号") { copyAccount() }
                    Button("复制密码") { copyPassword() }
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func badge(_ access: JLUSite.Access) -> some View {
        Text(access.rawValue)
            .font(.system(size: 9))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(access == .publicSite ? Color.green.opacity(0.15)
                        : (access == .campusOnly ? Color.orange.opacity(0.18)
                           : Color.blue.opacity(0.15)),
                        in: Capsule())
    }

    private func open(_ site: JLUSite) {
        guard let url = site.url else { return }
        NSWorkspace.shared.open(url)
        if site.supportsCredentialPrefill, !model.account.isEmpty {
            copyAccount()
        }
    }

    private func copyAccount() {
        guard !model.account.isEmpty else {
            flash("还没填账号——先到设置里填一次")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.account, forType: .string)
        flash("账号已复制：\(model.account)")
    }

    private func copyPassword() {
        guard let password = model.storedPasswordForPrefill(), !password.isEmpty else {
            flash("本机没有保存密码——先在设置里保存一次")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        let changeCount = pasteboard.changeCount
        flash("密码已复制，60 秒后自动清空剪贴板")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            // 只有剪贴板还是我们写的那一条才清，避免误删用户新复制的内容
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }

    private func flash(_ text: String) {
        copiedHint = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if copiedHint == text { copiedHint = nil }
        }
    }
}
