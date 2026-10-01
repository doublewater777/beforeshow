import Foundation

/// Small localization seam shared by the app and the widget extension.
///
/// SwiftUI can discover literal `Text` values automatically, but dynamic
/// strings returned from domain models, notifications, widgets, and Live
/// Activities need an explicit lookup. `Bundle.main` resolves to the app or
/// extension bundle at runtime, so the same code works in both targets.
enum BSLocalization {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    /// stringsdict 复数按传入 locale 选形式；不传时按系统语言选，
    /// 中文系统里 App 选 English 会得到「1 days」，所以跟随 App 所选语言。
    /// 只给复数格式传 locale：普通格式带 locale 会给 %lld 加千分位（2,026年）。
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        guard format.contains("%#@") else {
            return String(format: format, arguments: arguments)
        }
        return String(format: format, locale: selectedLocale, arguments: arguments)
    }

    private static var selectedLocale: Locale {
        guard let code = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?.string(forKey: "appLanguage"),
              !code.isEmpty else {
            return .current
        }
        return Locale(identifier: code)
    }
}
