import Foundation
import RevenueCat

/// 把 RevenueCat 的 `CustomerInfo` 变化同步到 `ProEntitlementStorage.appStorageKey`，
/// 保持 paywall / settings / quota gate 的现有 read path 不动。
///
/// 启动时 `BeforeShowApp.init()` 会调一次 `refreshFromServer()` 把 RC 服务端的
/// entitlement 拉回本地；之后 RC 在 purchase / restore / server-to-server
/// notification 等事件触发时也会回调 `purchases(_:receivedCustomerInfo:)`。
final class ProEntitlementSyncDelegate: NSObject, PurchasesDelegate, @unchecked Sendable {
    static let shared = ProEntitlementSyncDelegate()

    private let key = ProEntitlementStorage.appStorageKey

    func purchases(_ purchases: Purchases, receivedCustomerInfo info: CustomerInfo) {
        write(info)
    }

    /// 启动时主动拉一次，避免 paywall / gate 看到过期的本地状态。
    @MainActor
    func refreshFromServer() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            write(info)
        } catch {
            // 拉取失败保留 AppStorage 当前值；下次 purchase / delegate 触发会重写。
        }
    }

    private func write(_ info: CustomerInfo) {
        let state = RevenueCatProSubscriptionStore.entitlement(from: info) ?? .free
        let raw = ProEntitlementStorage.encode(state)
        // PurchasesDelegate 在主线程回调；UserDefaults 写主线程没问题。
        UserDefaults.standard.set(raw, forKey: key)
    }
}
