import SwiftUI

/// Liquid Glass 只在**菜单栏面板**里安全。
///
/// 真机崩溃栈（2026-11-03）：
///   objc_exception_rethrow → AppKit __NSWindowGetDisplayCycleObserverForLayout
///   → NSDisplayCycleFlush → CATransaction commit → SIGABRT
/// 也就是"自建 NSWindow 里渲染玻璃卡片"会在布局/显示周期抛 ObjC 异常。
/// 结论：独立窗口（向导/设置/详情/状态/门户）一律用普通材质，菜单面板才用玻璃。
enum AppearanceCompat {
    /// 全局兼容开关（设置里的"兼容模式"或 JLUGATE_COMPAT=1）：连菜单也不再用玻璃。
    nonisolated(unsafe) static var useGlass: Bool = {
        ProcessInfo.processInfo.environment["JLUGATE_COMPAT"] == "1" ? false : true
    }()

    static func apply(configFlag: Bool) {
        if ProcessInfo.processInfo.environment["JLUGATE_COMPAT"] == "1" { return }
        useGlass = !configFlag
    }
}

extension EnvironmentValues {
    /// 当前窗口是否允许液态玻璃（只有菜单栏面板是 true）。
    @Entry var glassAllowed: Bool = false
}

extension View {
    /// 卡片背景：允许玻璃时用玻璃，否则普通材质 + 描边。
    func jluGlassCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// 状态卡（带 tint）。
    func jluGlassStatus(cornerRadius: CGFloat = 16, tint: Color) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint, interactive: true))
    }

    /// 独立窗口里一律禁用玻璃（不需要手动加环境值）。
    func plainWindowChrome() -> some View {
        environment(\.glassAllowed, false)
    }
}

private struct GlassCardModifier: ViewModifier {
    @Environment(\.glassAllowed) private var glassAllowed
    let cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if glassAllowed && AppearanceCompat.useGlass {
            let base = tint.map {
                content.glassEffect(.regular.tint($0.opacity(0.5)).interactive(interactive),
                                    in: .rect(cornerRadius: cornerRadius))
            } ?? content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            return AnyView(base)
        }
        return AnyView(
            content
                .background((tint?.opacity(0.18) ?? Color.clear),
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }
}
