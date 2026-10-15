import Foundation

/// Small localization seam shared by the app and the widget extension.
///
/// Literal keys are typed as `LocalizedStringResource` so Xcode extracts them
/// into the target's String Catalog. Keys only known at runtime (enum raw
/// values, error messages) go through `text(key:)` / `format(key:)` and must
/// already exist in the catalog. `Bundle.main` resolves to the app or
/// extension bundle at runtime, so the same code works in both targets.
enum BSLocalization {
    static func text(_ resource: LocalizedStringResource) -> String {
        text(key: resource.key)
    }

    static func text(key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
        formatted(key: resource.key, arguments)
    }

    static func format(key: String, _ arguments: CVarArg...) -> String {
        formatted(key: key, arguments)
    }

    /// 仅复数格式传入 locale，避免普通整数格式出现千分位。
    private static func formatted(key: String, _ arguments: [CVarArg]) -> String {
        let format = text(key: key)
        guard format.contains("%#@") else {
            return String(format: format, arguments: arguments)
        }
        return String(format: format, locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier), arguments: arguments)
    }

}
