import Foundation
import RevenueCat

struct RevenueCatProSubscriptionStore: ProSubscriptionStore {
    /// Dashboard 当前 entitlement identifier 是 "beforeshow Pro"；
    /// 同时接受 "pro"，方便以后改成更短的 id。
    static let proEntitlementID = "beforeshow Pro"
    static let proEntitlementIDs: Set<String> = ["beforeshow Pro", "pro"]

    /// store product identifier → 内部 plan。
    /// App Store ID 和 Test Store 短 ID 都要认，
    /// 否则 Test Store offering 拉回来后会被全部丢掉。
    static let planForProductID: [String: ProSubscriptionPlan] = [
        ProSubscriptionCatalog.yearlyProductID: .yearly,
        "yearly": .yearly,
        "yearly.v2": .yearly,
        "yearly.trial3d": .yearly,
        ProSubscriptionCatalog.lifetimeProductID: .lifetime,
        "lifetime": .lifetime,
        "lifetime.v2": .lifetime,
        ProSubscriptionCatalog.yearlyDiscountProductID: .yearlyDiscount,
        "yearly.discount": .yearlyDiscount,
        ProSubscriptionCatalog.lifetimeDiscountProductID: .lifetimeDiscount,
        "lifetime.discount": .lifetimeDiscount,
    ]

    func loadProducts() async throws -> [ProSubscriptionProduct] {
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else { return [] }
        let packages = current.availablePackages
        // 试用资格必须在展示前确认：无资格用户看到「免费试用」会构成误导。
        // unknown 也按无资格处理（RC 建议 unknown 时展示正常价格）。
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: packages.map { $0.storeProduct.productIdentifier }
        )
        return packages
            .compactMap { package in
                Self.product(
                    from: package,
                    trialEligible: eligibility[package.storeProduct.productIdentifier]?.status == .eligible
                )
            }
            .sorted { lhs, rhs in
                ProSubscriptionPlan.allCases.firstIndex(of: lhs.plan) ?? 0
                    < ProSubscriptionPlan.allCases.firstIndex(of: rhs.plan) ?? 0
            }
    }

    func purchase(productID: String) async throws -> ProPurchaseOutcome {
        let offerings = try await Purchases.shared.offerings()
        guard let package = offerings.current?.availablePackages
                .first(where: { $0.storeProduct.productIdentifier == productID }) else {
            throw ProSubscriptionError.productNotFound
        }

        // 模型层不变量：已激活 Pro 时不能再购买挽留方案。
        // lifetimeDiscount 是 NonConsumable，App Store 不会自动取消已有订阅，
        // 允许通过会导致重复扣款；yearlyDiscount 会与已有订阅重叠续费。
        if let plan = Self.planForProductID[productID], plan.isWinback,
           let current = try await Self.currentEntitlement(), current.isProActive {
            throw ProSubscriptionError.winbackNotAvailableWhileActive
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            // RC 5.x async purchase 返回 PurchaseResultData 元组：
            // (transaction, customerInfo, userCancelled)。取消既可能是 flag，
            // 也可能是 ErrorCode.purchaseCancelledError。
            if result.userCancelled {
                throw ProSubscriptionError.purchaseCancelled
            }
            return Self.outcome(
                entitlement: Self.entitlement(from: result.customerInfo),
                entitlementPeriodType: Self.entitlementPeriodType(result.customerInfo),
                transaction: result.transaction,
                product: package.storeProduct
            )
        } catch {
            if Self.isPurchaseCancelled(error) {
                throw ProSubscriptionError.purchaseCancelled
            }
            throw error
        }
    }

    func restorePurchases() async throws -> ProEntitlementState {
        let info = try await Purchases.shared.restorePurchases()
        guard let state = Self.entitlement(from: info) else {
            throw ProSubscriptionError.nothingToRestore
        }
        return state
    }

    static func currentEntitlement() async throws -> ProEntitlementState? {
        let info = try await Purchases.shared.customerInfo()
        return entitlement(from: info)
    }

    static func isPurchaseCancelled(_ error: Error) -> Bool {
        (error as NSError).code == ErrorCode.purchaseCancelledError.rawValue
    }

    /// 把一次成功购买整理成 `ProPurchaseOutcome`。
    /// 权益为 nil（未拿到有效 Pro 权益）时按 free 返回，但 revenue 一定为 nil。
    static func outcome(
        entitlement: ProEntitlementState?,
        entitlementPeriodType: PeriodType?,
        transaction: StoreTransaction?,
        product: StoreProduct
    ) -> ProPurchaseOutcome {
        ProPurchaseOutcome(
            entitlement: entitlement ?? .free,
            transactionID: transaction?.transactionIdentifier,
            revenue: Self.revenue(
                entitlementPeriodType: entitlementPeriodType,
                transactionPrice: Self.transactionPrice(transaction),
                currencyCode: product.currencyCode
            )
        )
    }

    /// entitlement 的 periodType 反映本次交易落在哪种计费周期；权益缺失时为 nil。
    static func entitlementPeriodType(_ info: CustomerInfo) -> PeriodType? {
        proEntitlementIDs.lazy
            .compactMap { info.entitlements[$0] }
            .first?
            .periodType
    }

    /// 实收金额（纯函数，便于覆盖试用 / intro / 普通购买）
    ///
    /// 四条规则缺一不可：
    /// 1. `entitlementPeriodType == .normal`：试用 / intro 优惠虽然也会给 Pro 权益，
    ///    但当期没收钱，不能记成收入。
    /// 2. **只要交易实付金额**。商品标价不是实收金额：优惠 / 促销能使
    ///    实付低于标价，而 `periodType == .normal` 只说明权益在普通计费周期，
    ///    并不证明等于标价。取不到就上报 nil，不拿标价填空。
    /// 3. 金额 > 0：零元交易不是收入。
    /// 4. 有货币代码：避免把金额记成默认货币。
    static func revenue(
        entitlementPeriodType: PeriodType?,
        transactionPrice: Decimal?,
        currencyCode: String?
    ) -> ProPurchaseRevenue? {
        guard entitlementPeriodType == .normal else { return nil }
        guard let transactionPrice else { return nil }
        guard let currencyCode, !currencyCode.isEmpty else { return nil }
        guard transactionPrice > 0 else { return nil }
        return ProPurchaseRevenue(amount: transactionPrice, currency: currencyCode)
    }

    /// StoreKit 2 交易实付金额。iOS 15+ 可用；取不到（SK1 / 未公开）返回 nil。
    private static func transactionPrice(_ transaction: StoreTransaction?) -> Decimal? {
        guard let transaction,
              #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *),
              let price = transaction.sk2Transaction?.price else { return nil }
        return price
    }

    /// 把 RC 的 `CustomerInfo` 映射成本地 `ProEntitlementState`。
    /// 仅在 RC entitlement 名为 "pro" 时返回非空；否则视为 free。
    static func entitlement(from info: CustomerInfo) -> ProEntitlementState? {
        let entry = proEntitlementIDs.lazy.compactMap { info.entitlements[$0] }.first
        guard let entry else { return nil }
        return entitlement(
            isActive: entry.isActive,
            expirationDate: entry.expirationDate,
            productIdentifier: entry.productIdentifier
        )
    }

    /// `entitlement(from info:)` 的纯函数核心。拆出来便于在测试里直接喂基本类型，
    /// 不用手工构造 `CustomerInfo` / `EntitlementInfo`。
    /// - active → `.active`
    /// - expirationDate < referenceDate → `.expired`
    /// - 其他（包括 nil / 还没到过期时间）→ nil（视为 free）
    static func entitlement(
        isActive: Bool,
        expirationDate: Date?,
        productIdentifier: String,
        referenceDate: Date = Date()
    ) -> ProEntitlementState? {
        if isActive {
            return .active(productID: productIdentifier, expirationDate: expirationDate)
        }
        if let exp = expirationDate, exp < referenceDate {
            return .expired(productID: productIdentifier, expirationDate: exp)
        }
        return nil
    }

    private static func product(from package: Package, trialEligible: Bool) -> ProSubscriptionProduct? {
        let id = package.storeProduct.productIdentifier
        guard let plan = planForProductID[id] else { return nil }
        let fallback = ProSubscriptionCatalog.defaultProducts.first { $0.id == id }
        return ProSubscriptionProduct(
            id: id,
            plan: plan,
            displayName: package.storeProduct.localizedTitle,
            priceText: package.storeProduct.localizedPriceString,
            benefitCopy: fallback?.benefitCopy ?? [],
            isAvailable: true,
            perMonthEquivalentText: plan == .yearly
                ? Self.perMonthEquivalentText(for: package.storeProduct)
                : nil,
            trialText: plan == .yearly && trialEligible
                ? Self.freeTrialText(for: package.storeProduct)
                : nil,
            priceAmount: package.storeProduct.price,
            priceCurrency: package.storeProduct.currencyCode
        )
    }

    /// 免费试用文案（如「3 天免费试用」）。仅识别零价 introductory offer；
    /// 非天单位的配置不展示，避免与 ASC 实际配置不符的文案。
    private static func freeTrialText(for product: StoreProduct) -> String? {
        guard let discount = product.introductoryDiscount, discount.price == 0 else { return nil }
        return freeTrialText(periodUnit: discount.subscriptionPeriod.unit, value: discount.subscriptionPeriod.value)
    }

    static func freeTrialText(periodUnit: SubscriptionPeriod.Unit, value: Int) -> String? {
        guard periodUnit == .day else { return nil }
        return BSLocalization.format("免费试用 %lld 天", value)
    }

    /// 年度方案按月折算（如 $4.99/年 → 约 $0.42/月），用 RC 真实价格计算。
    private static func perMonthEquivalentText(for product: StoreProduct) -> String? {
        guard let period = product.subscriptionPeriod else { return nil }
        let months: Decimal
        switch period.unit {
        case .day: months = Decimal(period.value) / 30
        case .week: months = Decimal(period.value) * 12 / 52
        case .month: months = Decimal(period.value)
        case .year: months = Decimal(period.value) * 12
        @unknown default:
            return nil
        }
        guard months > 0 else { return nil }
        let monthly = product.price / months
        if let formatter = product.priceFormatter {
            return formatter.string(from: monthly as NSDecimalNumber)
        }
        guard let currencyCode = product.currencyCode else { return nil }
        return monthly.formatted(.currency(code: currencyCode))
    }
}
