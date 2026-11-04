import SwiftUI
import AppKit
import JLUGateCore

/// 地址输入：AppKit 原生 `NSTextField` + 输入格式化。
///
/// 为什么不用 SwiftUI 的 TextField：它每次把格式化后的字符串写回 binding，
/// 光标就会被重置到末尾——表现为"改不了前面的数字、退格删不掉、只能整行清空"。
/// AppKit 的 `NSTextField` 允许我们**自己控制光标位置**，这是唯一可靠的做法。
///
/// 行为：
/// - 只能输入数字（MAC 为十六进制），分隔符自动补；
/// - 只在"在末尾继续输入"时重排+补分隔符，光标始终跟在刚输入的字符后面；
/// - 在中间插入/删除时不重排，因此任意位置都能改；
/// - Enter → 交给外层（跳到下一项 / 下一步）。
struct AddressField: View {
    enum Kind {
        case ipv4
        case mac

        var placeholder: String { self == .ipv4 ? "192.168.1.10" : "02:00:00:00:00:01" }
        var groupSize: Int { self == .ipv4 ? 3 : 2 }
        var maxGroups: Int { self == .ipv4 ? 4 : 6 }
        var separator: Character { self == .ipv4 ? "." : ":" }
        var isHex: Bool { self == .mac }

        func isAllowed(_ character: Character) -> Bool {
            isHex ? character.isHexDigit : character.isNumber
        }
    }

    let kind: Kind
    @Binding var text: String
    var onSubmit: (() -> Void)?

    var body: some View {
        FormattedTextField(text: $text, kind: kind, onSubmit: onSubmit)
            .frame(height: 22)
            .frame(width: kind == .ipv4 ? 190 : 210)
    }
}

/// 一个行"标签 + 地址框"。
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
            Spacer(minLength: 0)
        }
    }
}

// MARK: - AppKit 实现

private struct FormattedTextField: NSViewRepresentable {
    @Binding var text: String
    let kind: AddressField.Kind
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = kind.placeholder
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.focusRingType = .default
        field.stringValue = text
        field.target = context.coordinator
        field.action = #selector(Coordinator.handleEnter(_:))
        // 让 Enter 直接走 action，而不是插入换行
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // 只有"外部改动"（载入配置 / 清空）才回灌；用户自己输入的由 AppKit 维护
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FormattedTextField

        init(parent: FormattedTextField) {
            self.parent = parent
        }

        @objc func handleEnter(_ sender: NSTextField) {
            parent.onSubmit?()
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true        // 吞掉回车，不把它插进文本
            }
            return false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }

            let selection = editor.selectedRange()
            let typed = editor.string
            let kind: AddressEditing.Kind = parent.kind == .ipv4 ? .ipv4 : .mac

            // 规则在 Core 里单测过：末尾输入才重排，中间编辑光标不动
            let edited = AddressEditing.apply(typed: typed,
                                              selectedLocation: selection.location,
                                              kind: kind)
            if edited.text != typed {
                field.stringValue = edited.text
                editor.string = edited.text
                editor.setSelectedRange(NSRange(location: edited.caret, length: 0))
            }
            parent.text = edited.text
        }
    }
}
