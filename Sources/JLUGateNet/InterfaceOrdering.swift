import Foundation

/// 网口列表的展示顺序：**正在用的排最前**，然后按"有线优先、有地址优先"。
/// 不做"随便排"——列表顺序本身就是给用户的提示。
public enum InterfaceOrdering {
    /// - Parameters:
    ///   - items: 全部候选
    ///   - active: 当前正在认证/已连接的网口名（没有就传 route 接口或 nil）
    public static func sorted(_ items: [InterfaceSnapshot], active: String?) -> [InterfaceSnapshot] {
        items.enumerated().sorted { lhs, rhs in
            let l = rank(lhs.element, active: active), r = rank(rhs.element, active: active)
            if l != r { return l < r }
            if lhs.element.index != rhs.element.index { return lhs.element.index < rhs.element.index }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    public static func rank(_ item: InterfaceSnapshot, active: String?) -> Int {
        if let active, item.name == active { return 0 }
        if item.isLoopback || VirtualInterfaceNames.isVirtual(item.name) { return 50 }
        if !item.isUp { return 40 }
        let wired = !item.isWireless
        let hasIP = item.ipv4 != nil
        switch (wired, hasIP) {
        case (true, true): return 10
        case (true, false): return 20
        case (false, true): return 30
        case (false, false): return 35
        }
    }
}
