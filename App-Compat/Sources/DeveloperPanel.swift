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
                Text(Copy.t("X01")).font(.headline)
                Text(Copy.t("X02"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                action(Copy.t("X03"), "square.and.arrow.up",
                       detail: Copy.t("X04")) {
                    model.exportDiagnostics()
                    hint = Copy.t("X05")
                }
                action(Copy.t("X06"), "doc.on.clipboard",
                       detail: Copy.t("X07")) {
                    model.copyDiagnostics()
                    hint = Copy.t("X08")
                }
                action(Copy.t("X09"), "qrcode",
                       detail: Copy.t("X10")) {
                    model.exportConfigCard()
                    hint = Copy.t("X11")
                }

                if let hint {
                    Text(hint).font(.caption2).foregroundStyle(.green)
                }

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.t("X12")).font(.caption).bold()
                    Text(Copy.t("X13"))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(FieldGuide.entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.term).font(.system(size: 10, weight: .medium))
                            Text(entry.explanation)
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
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
