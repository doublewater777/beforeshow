import Foundation

/// Small localization seam shared by the app and the widget extension.
///
/// SwiftUI can discover literal `Text` values automatically, but dynamic
/// strings returned from domain models, notifications, widgets, and Live
/// Activities need an explicit lookup. `Bundle.main` resolves to the app or
/// extension bundle at runtime, so the same code works in both targets.
enum BSLocalization {
    static func text(_ key: String) -> String {
        let localized = NSLocalizedString(key, bundle: .main, comment: "")
        guard localized == key,
              let fallback = countdownFallback(for: key, localeIdentifier: selectedLocale.identifier) else {
            return localized
        }
        return fallback
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// Dynamic countdown labels are shared by the app and widget targets. If a
    /// generated target-specific string table temporarily misses one of these
    /// keys, use the same wording as the widget table instead of leaking the
    /// Simplified-Chinese source key. An explicit resource localization always
    /// wins before this fallback runs.
    static func countdownFallback(for key: String, localeIdentifier: String) -> String? {
        switch languageKind(for: localeIdentifier) {
        case .english:
            switch key {
            case "距离开场": return "Until show starts"
            case "小时": return "hours"
            case "分钟": return "minutes"
            case "秒": return "seconds"
            default: return nil
            }
        case .traditionalChinese:
            switch key {
            case "距离开场": return "距離開場"
            case "小时": return "小時"
            case "分钟": return "分鐘"
            case "秒": return "秒"
            default: return nil
            }
        case .other:
            return nil
        }
    }

    private enum LanguageKind {
        case english
        case traditionalChinese
        case other
    }

    private static func languageKind(for localeIdentifier: String) -> LanguageKind {
        let identifier = localeIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if identifier.hasPrefix("en") {
            return .english
        }
        if identifier.hasPrefix("zh-hant")
            || identifier.hasPrefix("zh-tw")
            || identifier.hasPrefix("zh-hk")
            || identifier.hasPrefix("zh-mo") {
            return .traditionalChinese
        }
        return .other
    }

    /// AppLanguageManager persists the app override under this key. Reading it
    /// here keeps the shared localization seam independent from the app target,
    /// while still making an in-app language change affect generated labels.
    private static var selectedLocale: Locale {
        if let identifier = UserDefaults.standard.string(forKey: "appLanguage"), !identifier.isEmpty {
            return Locale(identifier: identifier)
        }
        return .autoupdatingCurrent
    }
}
