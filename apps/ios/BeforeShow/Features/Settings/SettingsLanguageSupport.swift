import Combine
import Foundation
import ObjectiveC
import WidgetKit

enum AppLanguage: String, CaseIterable, Identifiable, Equatable {
    case system = ""
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return BSLocalization.text("跟随系统")
        case .zhHans: return BSLocalization.text("简体中文")
        case .zhHant: return BSLocalization.text("繁體中文")
        case .en: return "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        case .en: return Locale(identifier: "en")
        }
    }

    var bundle: Bundle? {
        guard self != .system else {
            return AppLanguage.systemBundle()
        }
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// 系统语言对应的 `.lproj` bundle，按当前 `Locale.preferredLanguages` 实时匹配，
    /// 不依赖 `Bundle.main` 启动时缓存的 localizations。
    static func systemBundle() -> Bundle? {
        let supported = Bundle.main.localizations
        let preferred = Bundle.preferredLocalizations(
            from: supported,
            forPreferences: Locale.preferredLanguages
        )
        guard let code = preferred.first,
              let path = Bundle.main.path(forResource: code, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

/// In-app language override, active immediately without an app restart.
///
/// `BSLocalization` resolves through `Bundle.main.localizedString`, so swapping
/// `Bundle.main`'s class for `LanguageSwizzledBundle` makes every lookup hit the
/// selected `lproj`. `.system` resolves the device-language `lproj` explicitly
/// (via `AppLanguage.systemBundle()`), so switching back from a manual language
/// takes effect immediately instead of relying on `Bundle.main`'s launch-time choice.
nonisolated(unsafe) private var languageBundleAssociationKey: UInt8 = 0

private final class LanguageSwizzledBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let override = objc_getAssociatedObject(self, &languageBundleAssociationKey) as? Bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return override.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum AppLanguageManager {
    static let storageKey = "appLanguage"

    static var persisted: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    static func apply(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        // 组件进程读不到 App 私有 defaults，把语言选择同步到 App Group，让组件跟随。
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?.set(language.rawValue, forKey: storageKey)
        object_setClass(Bundle.main, LanguageSwizzledBundle.self)
        objc_setAssociatedObject(
            Bundle.main,
            &languageBundleAssociationKey,
            language.bundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

@MainActor
final class AppLanguageController: ObservableObject {
    static let shared = AppLanguageController()
    @Published var language: AppLanguage

    private init() {
        language = AppLanguageManager.persisted
    }

    func select(_ language: AppLanguage) {
        AppLanguageManager.apply(language)
        self.language = language
        // 语言变化本身不改变 widget 数据指纹，需要主动刷新让组件按新语言重渲染。
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// 在官网链接上追加当前 App 语言，让 App 内打开的页面跟随语言切换。
@MainActor
func localizedSiteURL(_ base: URL) -> URL {
    let language = AppLanguageController.shared.language
    guard language != .system else { return base }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []
    queryItems.append(URLQueryItem(name: "lang", value: language.rawValue))
    components?.queryItems = queryItems
    return components?.url ?? base
}
