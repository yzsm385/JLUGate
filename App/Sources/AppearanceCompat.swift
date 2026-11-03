import SwiftUI

/// 液态玻璃是 macOS 26 的新渲染路径；在虚拟机/老显卡/预览版系统上有已知的渲染崩溃。
/// 提供一个开关：完全绕开 `glassEffect`，用普通材质+圆角代替（外观略朴素，但稳）。
enum AppearanceCompat {
    /// 默认开玻璃；`JLUGATE_COMPAT=1` 或设置里 `compatibilityMode` 打开时改用普通材质。
    nonisolated(unsafe) static var useGlass: Bool = {
        if ProcessInfo.processInfo.environment["JLUGATE_COMPAT"] == "1" { return false }
        return true
    }()

    /// 从配置里读（设置页可切换，重启生效）。
    static func apply(configFlag: Bool) {
        if ProcessInfo.processInfo.environment["JLUGATE_COMPAT"] == "1" { return }
        useGlass = !configFlag
    }
}

extension View {
    /// 卡片背景：玻璃 或 普通材质（兼容模式）。
    func jluGlassCard(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// 状态卡用带 tint 的玻璃。
    func jluGlassStatus(cornerRadius: CGFloat = 16, tint: Color) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint, interactive: true))
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    var stroke: Bool = true

    init(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false, stroke: Bool = true) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.interactive = interactive
        self.stroke = stroke
    }

    func body(content: Content) -> some View {
        if AppearanceCompat.useGlass {
            let base = tint.map {
                content.glassEffect(.regular.tint($0.opacity(0.5)).interactive(interactive),
                                    in: .rect(cornerRadius: cornerRadius))
            } ?? content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            return AnyView(base)
        }
        return AnyView(
            content
                .background(tint?.opacity(0.18) ?? Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }
}
