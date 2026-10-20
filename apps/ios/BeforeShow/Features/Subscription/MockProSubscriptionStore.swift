import Foundation

actor MockProSubscriptionStore: ProSubscriptionStore {
    private let products: [ProSubscriptionProduct]
    private var entitlement: ProEntitlementState
    private var restorableEntitlement: ProEntitlementState?
    private var simulatedError: Error?
    /// true 时模拟免费试用 / 免费恢复：权益会生效，但没有实收金额。
    private var simulatedTrial = false

    init(
        products: [ProSubscriptionProduct] = ProSubscriptionCatalog.defaultProducts,
        entitlement: ProEntitlementState = .free,
        restorableEntitlement: ProEntitlementState? = nil,
        simulatedError: Error? = nil,
        simulatedTrial: Bool = false
    ) {
        self.products = products
        self.entitlement = entitlement
        self.restorableEntitlement = restorableEntitlement
        self.simulatedError = simulatedError
        self.simulatedTrial = simulatedTrial
    }

    func setSimulatedError(_ error: Error?) {
        self.simulatedError = error
    }

    func loadProducts() async throws -> [ProSubscriptionProduct] {
        if let error = simulatedError {
            throw error
        }
        return products.map { $0.markingAvailable() }
    }

    func purchase(productID: String) async throws -> ProPurchaseOutcome {
        if let error = simulatedError {
            throw error
        }
        guard products.contains(where: { $0.id == productID }) else {
            throw ProSubscriptionError.productNotFound
        }
        // 模型层不变量：已激活 Pro 时不能再购买挽留方案。
        // lifetimeDiscount 是 NonConsumable，App Store 不会自动取消已有订阅，
        // 允许通过会导致重复扣款；yearlyDiscount 会与已有订阅重叠续费。
        if let plan = ProSubscriptionPlan(productID: productID), plan.isWinback,
           entitlement.isProActive {
            throw ProSubscriptionError.winbackNotAvailableWhileActive
        }

        let purchased = ProEntitlementState.active(productID: productID, expirationDate: nil)
        entitlement = purchased
        restorableEntitlement = purchased
        // 正常成交：按 store 返回的真实价格给实收金额。
        // 免费试用 / 免费 intro 则无实收金额，UI 层不得据此记 `$revenue`。
        let revenue = simulatedTrial ? nil : products
            .first { $0.id == productID }?
            .revenueIfCharged
        return ProPurchaseOutcome(
            entitlement: purchased,
            transactionID: "mock-\(productID)",
            revenue: revenue
        )
    }

    func restorePurchases() async throws -> ProEntitlementState {
        if let error = simulatedError {
            throw error
        }
        if entitlement.isProActive {
            return entitlement
        }

        guard let restorableEntitlement else {
            throw ProSubscriptionError.nothingToRestore
        }

        entitlement = restorableEntitlement
        return restorableEntitlement
    }
}
