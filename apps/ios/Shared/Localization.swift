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

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}
