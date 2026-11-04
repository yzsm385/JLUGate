import SwiftUI
import JLUGateCore

/// 「诊断与开发」：平时用不到，排障/反馈时才需要的东西集中在这里。
/// （以前是三个并排按钮：导出、参数卡、诊断——占位置又容易误点。）
struct DeveloperPanel: View {
    @Environment(AppModel.self) private var model
    @State private var hint: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("诊断与开发").font(.headline)
                Text("平时不用；出问题要反馈时，用这里的导出。所有文件都已脱敏（账号 stu***、MAC 只留前三段）。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                action("导出诊断文件…", "square.and.arrow.up",
                       detail: "生成一份 txt（接口/路由/最近日志），用于反馈问题") {
                    model.exportDiagnostics()
                    hint = "已在 Finder 中打开诊断文件"
                }
                action("复制诊断到剪贴板", "doc.on.clipboard",
                       detail: "把同样的内容直接复制，粘贴给他人即可") {
                    model.copyDiagnostics()
                    hint = "诊断内容已复制"
                }
                action("复制参数卡", "qrcode",
                       detail: "当前配置的一段可粘贴文本（不含密码），换机时可直接导入") {
                    model.exportConfigCard()
                    hint = "参数卡已复制"
                }

                if let hint {
                    Text(hint).font(.caption2).foregroundStyle(.green)
                }
            }
            .padding(14)
        }
    }

    private func action(_ title: String, _ symbol: String, detail: String,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(.title3).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
