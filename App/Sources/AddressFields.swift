import SwiftUI
import JLUGateCore

/// 地址输入：**SwiftUI 圆角小框**（每段一个 `TextField(.roundedBorder)`，段间是分隔符）。
///
/// 为什么用它：圆角框是系统标准样式，外观、深浅色、字体缩放都跟系统一致；
/// 不自己画 AppKit 方框，也就不需要维护 NSTextField 的字段编辑器状态。
///
/// 键盘：
/// - 输满一段（IP 3 位 / MAC 2 位）自动跳下一段
/// - **Enter**：下一段；最后一段触发外层「下一步/完成」
/// - **← / →**：跨段
/// - **⌫**：当前段为空时退回上一段
struct AddressField: View {
    enum Kind {
        case ipv4
        case mac

        var count: Int { self == .ipv4 ? 4 : 6 }
        var maxLength: Int { self == .ipv4 ? 3 : 2 }
        var separator: String { self == .ipv4 ? "·" : ":" }
        var segmentWidth: CGFloat { self == .ipv4 ? 42 : 26 }
        var isHex: Bool { self == .mac }

        func isAllowed(_ character: Character) -> Bool {
            isHex ? character.isHexDigit : character.isNumber
        }
    }

    let kind: Kind
    @Binding var text: String
    var onSubmit: (() -> Void)?

    @State private var parts: [String]
    @FocusState private var focused: Int?

    init(kind: Kind, text: Binding<String>, onSubmit: (() -> Void)? = nil) {
        self.kind = kind
        self._text = text
        self.onSubmit = onSubmit
        _parts = State(initialValue: AddressField.split(text.wrappedValue, kind: kind))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(parts.indices, id: \.self) { index in
                TextField("", text: binding(for: index))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)      // 系统圆角框
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: kind.segmentWidth, height: 22)
                    .focused($focused, equals: index)
                    .onSubmit { advance(from: index) }
                    .onKeyPress(.leftArrow) {
                        guard focused == index, index > 0 else { return .ignored }
                        focused = index - 1
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard focused == index, index + 1 < parts.count else { return .ignored }
                        focused = index + 1
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        guard focused == index, parts[index].isEmpty, index > 0 else { return .ignored }
                        focused = index - 1
                        return .handled
                    }

                if index < parts.count - 1 {
                    Text(kind.separator)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(height: 22)
                }
            }
        }
        .onAppear {
            let incoming = Self.split(text, kind: kind)
            if incoming != parts { parts = incoming }
        }
        .onChange(of: text) { _, newValue in
            // 自己写出去的值会立刻回流：和当前拼接结果一样就忽略。
            // 不一样才说明是外部改动（预填/清空/切换档案）。
            let joined = parts.joined(separator: kind.separator)
            guard newValue != joined else { return }
            let incoming = Self.split(newValue, kind: kind)
            guard incoming != parts else { return }
            parts = incoming
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { parts[index] },
            set: { newValue in
                guard parts.indices.contains(index) else { return }
                let previous = parts[index]
                var filtered = newValue.filter { kind.isAllowed($0) }
                if kind.isHex { filtered = filtered.lowercased() }
                let value = String(filtered.prefix(kind.maxLength))
                parts[index] = value
                emit()
                if value.count == kind.maxLength, previous.count < kind.maxLength,
                   index + 1 < parts.count, focused == index {
                    focused = index + 1
                }
            })
    }

    private func advance(from index: Int) {
        if index + 1 < parts.count {
            focused = index + 1
        } else {
            onSubmit?()
        }
    }

    private func emit() {
        let joined = parts.joined(separator: kind.separator)
        guard joined != text else { return }
        text = joined
    }

    static func split(_ text: String, kind: Kind) -> [String] {
        let pieces = text.split(separator: Character(kind == .ipv4 ? "." : ":"),
                                omittingEmptySubsequences: false).map(String.init)
        var result = Array(pieces.prefix(kind.count))
        while result.count < kind.count { result.append("") }
        return result
    }
}

/// 一行"标签 + 地址框"，含义写在字段下面。
struct LabeledAddressField: View {
    let title: String
    let kind: AddressField.Kind
    @Binding var text: String
    var hint: String?
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 64, alignment: .leading)
                    .foregroundStyle(.secondary)
                AddressField(kind: kind, text: $text, onSubmit: onSubmit)
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 72)
            }
        }
    }
}
