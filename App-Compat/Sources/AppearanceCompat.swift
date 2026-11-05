import SwiftUI

/// 旧版适配（macOS 14+）：**完全不用 Liquid Glass**。
///
/// `glassEffect` 是 macOS 26 才有的 API，旧系统上调用会 unrecognized selector 直接崩。
/// 这一份把所有"玻璃卡片"统一退化成普通材质（`.regularMaterial`）+ tint + 描边，
/// 保留和新版一样的接口（`jluGlassCard` / `jluGlassStatus` / `glassAllowed` / `plainWindowChrome`），
/// 这样 App 层其余代码不用改，直接编译就能跑在 macOS 14 上。
///
/// 新版（macOS 26）的 Liquid Glass 实现在 `App/Sources/AppearanceCompat.swift`，
/// 两个包分别发布、互不影响。
enum AppearanceCompat {
    /// 兼容开关：旧版里玻璃永远是关的（没有玻璃可开）。
    /// 保留这个静态变量是为了让 `AppModel` 里 `AppearanceCompat.apply(...)` 仍能编译。
    nonisolated(unsafe) static var useGlass: Bool = false

    static func apply(configFlag: Bool) {
        // 旧版不提供玻璃，兼容模式开关在这里是空操作
        useGlass = false
    }
}

private struct GlassAllowedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// 当前窗口是否允许液态玻璃。旧版里永远是 false（没有玻璃）。
    /// 用 EnvironmentKey 而不是 @Entry：@Entry 在不同系统版本上可用性不一致，
    /// EnvironmentKey 从 macOS 11 起就在，最稳。
    var glassAllowed: Bool {
        get { self[GlassAllowedKey.self] }
        set { self[GlassAllowedKey.self] = newValue }
    }
}

extension View {
    /// 卡片背景：旧版一律普通材质 + 描边。
    func jluGlassCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// 状态卡（带 tint）。
    func jluGlassStatus(cornerRadius: CGFloat = 16, tint: Color) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// 独立窗口里一律禁用玻璃（旧版本来就禁，这里保持接口一致）。
    func plainWindowChrome() -> some View {
        environment(\.glassAllowed, false)
    }
}

private struct GlassCardModifier: ViewModifier {
    @Environment(\.glassAllowed) private var glassAllowed
    let cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        // 旧版：无脑走普通材质。tint 给一点点底色区分状态卡。
        content
            .background((tint?.opacity(0.18) ?? Color.clear),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
