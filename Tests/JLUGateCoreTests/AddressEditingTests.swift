import Foundation
import Testing
@testable import JLUGateCore

@Suite("地址输入：末尾输入才重排，中间编辑光标不动")
struct AddressEditingTests {
    @Test("在末尾连续输入：自动补分隔符，光标跟在后面")
    func typingAtEnd() {
        let result = AddressEditing.apply(typed: "192", selectedLocation: 3, kind: .ipv4)
        #expect(result.text == "192.")
        #expect(result.caret == 4)

        let next = AddressEditing.apply(typed: "192.168", selectedLocation: 7, kind: .ipv4)
        #expect(next.text == "192.168.")
        #expect(next.caret == 8)
    }

    @Test("在中间编辑：不重排，光标留在原处（真机 bug 的核心）")
    func editingInMiddle() {
        let typed = "192.168.1.10"
        let result = AddressEditing.apply(typed: typed, selectedLocation: 2, kind: .ipv4)
        #expect(result.text == typed, "中间编辑不该被格式化")
        #expect(result.caret == 2)
    }

    @Test("在中间删除：同样不重排")
    func deletingInMiddle() {
        // 删掉最后一位后的样子；光标停在中间 → 不应被补分隔符
        let typed = "203.0.113."
        let result = AddressEditing.apply(typed: typed, selectedLocation: 5, kind: .ipv4)
        #expect(result.text == typed)
        #expect(result.caret == 5)
    }

    @Test("非法字符被过滤，光标相应回退")
    func filtersInvalid() {
        let result = AddressEditing.apply(typed: "19a2", selectedLocation: 4, kind: .ipv4)
        #expect(result.text == "192.")
    }

    @Test("MAC：每 2 位补冒号")
    func mac() {
        let result = AddressEditing.apply(typed: "0200", selectedLocation: 4, kind: .mac)
        #expect(result.text == "02:00:")
        #expect(result.caret == 6)
    }

    @Test("粘贴带分隔符的完整地址：规整后仍是同一个地址")
    func paste() {
        let result = AddressEditing.apply(typed: "192.168.1.10", selectedLocation: 12, kind: .ipv4)
        #expect(result.text == "192.168.1.10")
    }
}
