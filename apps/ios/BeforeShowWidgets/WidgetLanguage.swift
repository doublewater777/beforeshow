import Foundation
import ObjectiveC

// 组件进程与 App 进程隔离：App 内切语言只 swizzle 了 App 进程的 Bundle.main，
// 组件进程读不到，一直按系统语言渲染。这里在组件进程启动时读 App Group 里
// 同步过来的语言选择，对组件自己的 Bundle.main 做同样的替换，让 BSLocalization
// 与 SwiftUI Text("key") 都落到所选 lproj。未选择(跟随系统)时保持原生行为。
nonisolated(unsafe) private var widgetLanguageBundleAssociationKey: UInt8 = 0

private final class WidgetLanguageSwizzledBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let override = objc_getAssociatedObject(self, &widgetLanguageBundleAssociationKey) as? Bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return override.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum WidgetLanguage {
    static func applyAppLanguageSelection() {
        guard let code = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?.string(forKey: "appLanguage"),
              !code.isEmpty,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let override = Bundle(path: path) else {
            return
        }
        object_setClass(Bundle.main, WidgetLanguageSwizzledBundle.self)
        objc_setAssociatedObject(
            Bundle.main,
            &widgetLanguageBundleAssociationKey,
            override,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}