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
        var segmentWidth: CGFloat { self == .ipv4 ? 44 : 32 }
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalWidth: CGFloat {
        let segments = kind.segmentWidth * CGFloat(kind.count)
        let gaps = 3 * CGFloat(kind.count - 1) * 2
        let separators = 12 * CGFloat(kind.count - 1)
        return segments + gaps + separators + 6
    }
}

/// 一行"标签 + 地址框"，标签列固定 72pt，所有行左对齐。
struct LabeledAddressField: View {
    let title: String
    let kind: AddressField.Kind
    @Binding var text: String
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(.secondary)
            AddressField(kind: kind, text: $text, onSubmit: onSubmit)
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
        container.setSegments(Coordinator.split(text, kind: kind))
        return container
    }

    func updateNSView(_ container: SegmentedContainer, context: Context) {
        context.coordinator.parent = self
        // 只处理"外部改动"（载入配置 / 清空）；用户输入由 AppKit 自己维护
        let incoming = Coordinator.split(text, kind: kind)
        if container.currentSegments() != incoming, !container.isEditing {
            container.setSegments(incoming)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SegmentedAddressField
        weak var container: SegmentedContainer?

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
                  let container, let index = container.index(of: field) else { return }
            var value = field.stringValue.filter { parent.kind.isAllowed($0) }
            if parent.kind.isHex { value = value.lowercased() }
            value = String(value.prefix(parent.kind.maxLength))
            if value != field.stringValue {
                field.stringValue = value
                field.currentEditor()?.selectedRange = NSRange(location: value.count, length: 0)
            }
            container.commit(segment: index, value: value)

            // 输满一段且光标在末尾 → 自动跳下一段
            if value.count == parent.kind.maxLength, index + 1 < parent.kind.count,
               let editor = field.currentEditor(), editor.selectedRange.location >= value.count {
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
        var x: CGFloat = 0
        for (index, field) in fields.enumerated() {
            field.frame = NSRect(x: x, y: 1, width: kind.segmentWidth, height: 22)
            x += kind.segmentWidth
            if index < labels.count {
                labels[index].frame = NSRect(x: x, y: 3, width: 12, height: 18)
                x += 12
            }
        }
        frame.size.width = x
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
