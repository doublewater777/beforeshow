import Foundation
import WidgetKit

/// 推荐需要、只能问系统的事实：是否已添加「开场前」小组件。
/// 结果缓存在本机，主卡同步读取；对账时刷新。
@MainActor
enum FeatureUsageEnvironment {
    nonisolated static let widgetKey = "FeatureUsage.hasInstalledWidget"

    static var cached: FeatureUsageFacts {
        FeatureUsageFacts(hasInstalledWidget: UserDefaults.standard.bool(forKey: widgetKey))
    }

    @discardableResult
    static func refresh() async -> FeatureUsageFacts {
        let facts = FeatureUsageFacts(hasInstalledWidget: await installedWidget() ?? cached.hasInstalledWidget)
        UserDefaults.standard.set(facts.hasInstalledWidget, forKey: widgetKey)
        return facts
    }

    private static func installedWidget() async -> Bool? {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let widgets):
                    continuation.resume(returning: widgets.contains { BeforeShowWidgetKind.all.contains($0.kind) })
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
