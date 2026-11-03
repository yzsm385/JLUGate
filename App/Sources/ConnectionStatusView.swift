import SwiftUI
import JLUGateCore

/// 「连接结果」小窗：点完成/登录之后立刻能看到结果，而不是去菜单栏里找错误。
struct ConnectionStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.statusTitle).font(.headline)
                    Text(model.detailLine).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
            }

            if case .failed(let error) = model.state {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.userMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if error.requiresUserAction {
                        Text("需要你处理一下；改完后点「重试」。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !model.recentLog.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.recentLog.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.retry()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    model.presentNetworkDetail()
                } label: {
                    Label("网络详情", systemImage: "network")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("关闭") { model.closeConnectionStatus() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear { model.refreshDiagnostics() }
    }

    private var icon: String {
        switch model.state {
        case .online: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "circle.dashed"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch model.state {
        case .online: .green
        case .failed: .red
        case .idle: .secondary
        default: .orange
        }
    }
}
