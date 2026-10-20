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

/// 一次购买的结果：本地权益 + 商店交易事实。
///
/// `revenue` 是这次交易**真实收到的现金**，不取商品标价：商品标价会把免费试用 /
/// 已拥有 / 恢复误记成正收入。拿不到可信实收金额时为 nil，即不上报 `$revenue`。
struct ProPurchaseOutcome: Equatable {
    let entitlement: ProEntitlementState
    /// Store 交易标识；用于 `$revenue` 幂等去重。
    let transactionID: String?
    /// 实收金额与货币；免费试用 / 免费恢复 / 无法确认为零时为 nil。
    let revenue: ProPurchaseRevenue?

    init(
        entitlement: ProEntitlementState,
        transactionID: String?,
        revenue: ProPurchaseRevenue? = nil
    ) {
        self.entitlement = entitlement
        self.transactionID = transactionID
        self.revenue = revenue
    }

    var isProActive: Bool { entitlement.isProActive }
}

/// 实收金额：`$revenue` 的唯一可信来源。
struct ProPurchaseRevenue: Equatable {
    let amount: Decimal
    let currency: String

    init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}
