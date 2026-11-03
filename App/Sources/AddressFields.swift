import SwiftUI
import JLUGateCore

/// 最初那种**分段格子**：每段一个输入框，段间是分隔符。
///
/// 三个细节：
/// 1. 分隔符用中点 `·` / 冒号 `:`，和数字同字体、同高度 → 永远在同一行中线上；
/// 2. 整个控件左对齐，标签列固定宽度，所有行起始位置一致；
/// 3. 自己改动只往下写，不回灌，所以退格删掉的内容不会被自动填回来。
struct AddressField: View {
    enum Kind {
        case ipv4
        case mac

        var count: Int { self == .ipv4 ? 4 : 6 }
        var maxLength: Int { self == .ipv4 ? 3 : 2 }
        var separator: String { self == .ipv4 ? "·" : ":" }
        var segmentWidth: CGFloat { self == .ipv4 ? 46 : 34 }
    }

    let kind: Kind
    @Binding var text: String

    @State private var parts: [String]
    @State private var lastEmitted = ""
    @FocusState private var focused: Int?

    init(kind: Kind, text: Binding<String>) {
        self.kind = kind
        _text = text
        _parts = State(initialValue: AddressField.split(text.wrappedValue, kind: kind))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(parts.indices, id: \.self) { index in
                TextField("", text: binding(for: index))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: kind.segmentWidth, height: 24)
                    .focused($focused, equals: index)

                if index < parts.count - 1 {
                    Text(kind.separator)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)      // 与输入框同高 → 中线对齐
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // 整块左对齐
        .onAppear {
            parts = Self.split(text, kind: kind)
            lastEmitted = text
        }
        .onChange(of: text) { _, newValue in
            guard newValue != lastEmitted else { return }   // 自己写的改动不回灌
            parts = Self.split(newValue, kind: kind)
            lastEmitted = newValue
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { parts[index] },
            set: { newValue in
                let filtered = kind == .ipv4
                    ? newValue.filter(\.isNumber)
                    : newValue.filter(\.isHexDigit).lowercased()
                parts[index] = String(filtered.prefix(kind.maxLength))
                emit()
                if parts[index].count == kind.maxLength, index + 1 < parts.count {
                    focused = index + 1
                }
            })
    }

    private func emit() {
        let joined = Self.join(parts, kind: kind)
        lastEmitted = joined
        text = joined
    }

    static func split(_ value: String, kind: Kind) -> [String] {
        kind == .ipv4 ? FieldFormatting.splitIPv4(value) : FieldFormatting.splitMAC(value)
    }

    static func join(_ parts: [String], kind: Kind) -> String {
        kind == .ipv4 ? FieldFormatting.joinIPv4(parts) : FieldFormatting.joinMAC(parts)
    }
}

/// 一行"标签 + 分段输入"，标签列固定 72pt，所有行左对齐且起始位置一致。
struct LabeledAddressField: View {
    let title: String
    let kind: AddressField.Kind
    @Binding var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            AddressField(kind: kind, text: $text)
        }
    }
}
