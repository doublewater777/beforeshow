import Foundation

enum ProSubscriptionError: Error, Equatable {
    case productNotFound
    case nothingToRestore
    case purchaseCancelled
    /// 挽留方案（特惠年度 / 特惠终身）只在用户从免费 / 过期状态购买时可用；
    /// Pro 已启用时再购买会与已有订阅重叠，模型层直接拒绝以避免重复扣款。
    case winbackNotAvailableWhileActive
}

protocol ProSubscriptionStore: Sendable {
    func loadProducts() async throws -> [ProSubscriptionProduct]
    func purchase(productID: String) async throws -> ProPurchaseOutcome
    func restorePurchases() async throws -> ProEntitlementState
}

/// 一次购买的结果：本地权益 + 商店交易标识。
/// 交易标识用于 `$revenue` 幂等去重（同一笔交易只记一次营收）。
struct ProPurchaseOutcome: Equatable {
    let entitlement: ProEntitlementState
    /// Store 交易标识；恢复 / 免费试用等非新增收入场景可能为 nil。
    let transactionID: String?

    init(entitlement: ProEntitlementState, transactionID: String?) {
        self.entitlement = entitlement
        self.transactionID = transactionID
    }

    var isProActive: Bool { entitlement.isProActive }
}
