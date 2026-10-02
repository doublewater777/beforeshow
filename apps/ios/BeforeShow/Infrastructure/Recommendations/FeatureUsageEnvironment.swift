import CloudKit
import Foundation
import WidgetKit

/// 推荐需要、只能问系统的事实：是否已添加「开场前」小组件、iCloud 是否可用（同行的前提）。
/// 结果缓存在本机，主卡同步读取；对账时刷新。
@MainActor
enum FeatureUsageEnvironment {
    nonisolated static let widgetKey = "FeatureUsage.hasInstalledWidget"
    nonisolated static let iCloudKey = "FeatureUsage.isICloudAvailable"

    static var cached: FeatureUsageFacts {
        FeatureUsageFacts(
            hasInstalledWidget: UserDefaults.standard.bool(forKey: widgetKey),
            isICloudAvailable: UserDefaults.standard.bool(forKey: iCloudKey)
        )
    }

    @discardableResult
    static func refresh() async -> FeatureUsageFacts {
        async let widget = installedWidget()
        async let iCloud = iCloudAvailable()
        let previous = cached
        let facts = FeatureUsageFacts(
            hasInstalledWidget: await widget ?? previous.hasInstalledWidget,
            isICloudAvailable: await iCloud ?? previous.isICloudAvailable
        )
        UserDefaults.standard.set(facts.hasInstalledWidget, forKey: widgetKey)
        UserDefaults.standard.set(facts.isICloudAvailable, forKey: iCloudKey)
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

    private static func iCloudAvailable() async -> Bool? {
        let container = CKContainer(identifier: CloudKitCompanionSharingService.defaultContainerIdentifier)
        guard let status = try? await container.accountStatus() else { return nil }
        return status == .available
    }
}
