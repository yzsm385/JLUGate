import SwiftUI
import AppKit
import JLUGateCore

/// 地址输入：**分段格子**（每段一个原生输入框，段间是分隔符）。
///
/// 用 AppKit 而不是 SwiftUI 的原因：SwiftUI 的分段 TextField 在每次输入重排时
/// 会重建子视图、把光标打回末尾——表现就是"前面的格子点进去也改不了，只能整行清空"。
/// 原生 `NSTextField` 由我们直接控制焦点与光标。
///
/// 键盘：
/// - **Enter**：跳到下一段（最后一段 → 触发外层"下一步/完成"）
/// - **← / →**：在段首/段尾时切到相邻段
/// - **⌫**：当前段为空时退回上一段
struct AddressField: View {
    enum Kind {
        case ipv4
        case mac

        var placeholder: String { self == .ipv4 ? "IP" : "MAC" }
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

    var body: some View {
        SegmentedAddressField(kind: kind, text: $text, onSubmit: onSubmit)
            .frame(width: totalWidth, height: 24)
    }

    private var totalWidth: CGFloat {
        let segments = kind.segmentWidth * CGFloat(kind.count)
        let separators = 10 * CGFloat(kind.count - 1)
        return segments + separators + 2
    }
}

/// 一行"标签 + 地址框"，标签列固定 72pt，所有行左对齐。
struct LabeledAddressField: View {
    let title: String
    let kind: AddressField.Kind
    @Binding var text: String
    /// 这个字段是什么意思——直接挂在字段下面，不另开说明区
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

// MARK: - AppKit 分段输入

struct SegmentedAddressField: NSViewRepresentable {
    let kind: AddressField.Kind
    @Binding var text: String
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> SegmentedContainer {
        let container = SegmentedContainer(kind: kind, coordinator: context.coordinator)
        context.coordinator.container = container
        container.build()
        context.coordinator.lastEmitted = text
        container.setSegments(Coordinator.split(text, kind: kind))
        return container
    }

    func updateNSView(_ container: SegmentedContainer, context: Context) {
        context.coordinator.parent = self
        // 只处理**真正的外部改动**（载入配置 / 清空）。
        // 关键：用 lastEmitted 比对，而不是和 SwiftUI 的当前值比对——
        // 否则别处一刷新（比如在另一个框里打字），拿到的旧值会把这里正在输的内容清空。
        guard text != context.coordinator.lastEmitted else { return }
        context.coordinator.lastEmitted = text
        container.setSegments(Coordinator.split(text, kind: kind))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SegmentedAddressField
        weak var container: SegmentedContainer?
        /// 最后一次由本控件写出去的值（用来区分"外部改动"和"回灌"）
        var lastEmitted = ""

        init(parent: SegmentedAddressField) { self.parent = parent }

        static func split(_ text: String, kind: AddressField.Kind) -> [String] {
            let parts = text.split(separator: Character(kind == .ipv4 ? "." : ":"),
                                   omittingEmptySubsequences: false).map(String.init)
            var result = Array(parts.prefix(kind.count))
            while result.count < kind.count { result.append("") }
            return result
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let container, let index = container.index(of: field),
                  let editor = field.currentEditor() as? NSTextView else { return }

            // 必须读**字段编辑器**里的内容：正在编辑时 field.stringValue 可能是旧值，
            // 拿它去截断会把刚敲的字符吞掉，还会引发跳格。
            let typed = editor.string
            var filtered = typed.filter { parent.kind.isAllowed($0) }
            if parent.kind.isHex { filtered = filtered.lowercased() }
            let value = String(filtered.prefix(parent.kind.maxLength))

            if value != typed {
                editor.string = value
                editor.selectedRange = NSRange(location: value.count, length: 0)
            }
            container.commit(segment: index, value: value)

            // 只有"刚好输满这一段、光标在末尾"才跳下一段（MAC 两字符、IP 三字符）
            if value.count == parent.kind.maxLength, index + 1 < parent.kind.count,
               editor.selectedRange.location >= value.count {
                container.focus(index + 1)
            }
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            guard let container else { return false }
            let index = container.index(of: control as? NSTextField)
            let careful: Int = index ?? 0
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if careful + 1 < parent.kind.count {
                    container.focus(careful + 1)
                } else {
                    parent.onSubmit?()
                }
                return true
            case #selector(NSResponder.moveRight(_:)):
                if textView.selectedRange.location >= (control as? NSTextField)?.stringValue.count ?? 0,
                   careful + 1 < parent.kind.count {
                    container.focus(careful + 1)
                    return true
                }
                return false
            case #selector(NSResponder.moveLeft(_:)):
                if textView.selectedRange.location == 0, careful > 0 {
                    container.focus(careful - 1)
                    return true
                }
                return false
            case #selector(NSResponder.deleteBackward(_:)):
                if (control as? NSTextField)?.stringValue.isEmpty == true, careful > 0 {
                    container.focus(careful - 1)
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}

/// 一个横向排布若干 `NSTextField` 的容器，自己管焦点。
@MainActor
final class SegmentedContainer: NSView {
    let kind: AddressField.Kind
    private let coordinator: SegmentedAddressField.Coordinator
    private var fields: [NSTextField] = []
    private var labels: [NSTextField] = []
    private var highlighter = false

    var isEditing: Bool { fields.contains { $0.currentEditor() != nil } }

    init(kind: AddressField.Kind, coordinator: SegmentedAddressField.Coordinator) {
        self.kind = kind
        self.coordinator = coordinator
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    func build() {
        for index in 0..<kind.count {
            let field = NSTextField()
            field.delegate = coordinator
            field.alignment = .center
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            field.bezelStyle = .roundedBezel
            field.isBordered = true
            field.focusRingType = .default
            field.translatesAutoresizingMaskIntoConstraints = true
            addSubview(field)
            fields.append(field)
            if index < kind.count - 1 {
                let label = NSTextField(labelWithString: kind.separator)
                label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
                label.textColor = .secondaryLabelColor
                label.alignment = .center
                addSubview(label)
                labels.append(label)
            }
        }
    }

    override func layout() {
        super.layout()
        // 绝不在 layout() 里修改**自己**的 frame：那会让窗口再次 needsLayout，
        // 触发 AppKit 的 "more Layout Window passes than there are views" 异常
        // （这就是点设置闪退的原因）。
        var x: CGFloat = 0
        let height = max(bounds.height, 24)
        for (index, field) in fields.enumerated() {
            field.frame = NSRect(x: x, y: (height - 22) / 2, width: kind.segmentWidth, height: 22)
            x += kind.segmentWidth
            if index < labels.count {
                labels[index].frame = NSRect(x: x, y: (height - 18) / 2, width: 12, height: 18)
                x += 12
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        let width = kind.segmentWidth * CGFloat(kind.count) + 12 * CGFloat(kind.count - 1)
        return NSSize(width: width, height: 24)
    }

    func index(of field: NSTextField?) -> Int? {
        guard let field else { return nil }
        return fields.firstIndex(of: field)
    }

    func currentSegments() -> [String] { fields.map(\.stringValue) }

    func setSegments(_ values: [String]) {
        for (field, value) in zip(fields, values) { field.stringValue = value }
    }

    func commit(segment index: Int, value: String) {
        guard index < fields.count else { return }
        var parts = currentSegments()
        parts[index] = value
        let joined = parts.joined(separator: String(kind.separator))
        coordinator.lastEmitted = joined
        coordinator.parent.text = joined
    }

    func focus(_ index: Int) {
        guard fields.indices.contains(index) else { return }
        window?.makeFirstResponder(fields[index])
        if let editor = fields[index].currentEditor() {
            let length = fields[index].stringValue.count
            editor.selectedRange = NSRange(location: length, length: 0)
        }
    }
}
