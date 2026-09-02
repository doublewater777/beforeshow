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
    func purchase(productID: String) async throws -> ProEntitlementState
    func restorePurchases() async throws -> ProEntitlementState
}
