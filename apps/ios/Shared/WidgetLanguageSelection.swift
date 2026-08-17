import Foundation

/// 组件进程语言覆盖的纯决策层（App 与组件 target 共用，可直接单测）。
///
/// 组件进程可能在 App 切语言后继续存活：`reloadAllTimelines()` 不保证终止并重启
/// extension 进程。所以「应用语言选择」必须可重复调用、且可回退：选了具体语言
/// → 覆盖到对应 lproj；跟随系统（无值 / 空串）→ 覆盖必须被清空，而不是保留
/// 上一次的手动语言。
enum WidgetLanguageSelection {
    static func override(code: String?, bundleForCode: (String) -> Bundle?) -> Bundle? {
        guard let code, !code.isEmpty else { return nil }
        return bundleForCode(code)
    }
}
