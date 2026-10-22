import RevenueCat
import XCTest
@testable import BeforeShow

/// PR #357 review P2：文案与曝光必须来自同一次分组取值。
final class WinbackCopyExperimentTests: XCTestCase {
    /// 未命中（flag 没加载 / 关闭）→ control，且标记未解析。
    func testUnresolvedFlagFallsBackToControl() {
        let snapshot = WinbackCopyExperiment.resolve(variantKey: nil)
        XCTAssertEqual(snapshot.variant, .control)
        XCTAssertFalse(snapshot.isFlagResolved)
    }

    /// flag 命中 access → access，且标记已解析。
    func testResolvedFlagUsesVariant() {
        let snapshot = WinbackCopyExperiment.resolve(variantKey: "access")
        XCTAssertEqual(snapshot.variant, .access)
        XCTAssertTrue(snapshot.isFlagResolved)
    }

    /// 真实 control 分组 vs flag 未加载：文案相同，但分组语义必须可区分，
    /// 否则实验数据会把「没加载」混进 control 组。
    func testRealControlIsDistinguishableFromFallback() {
        let realControl = WinbackCopyExperiment.resolve(variantKey: "control")
        let fallback = WinbackCopyExperiment.resolve(variantKey: nil)

        XCTAssertEqual(realControl.variant, .control)
        XCTAssertEqual(fallback.variant, .control)
        XCTAssertTrue(realControl.isFlagResolved)
        XCTAssertFalse(fallback.isFlagResolved)
        XCTAssertNotEqual(realControl.isFlagResolved, fallback.isFlagResolved)
    }

    /// 非法值不能当成有效分组。
    func testInvalidVariantValueFallsBackToControl() {
        let snapshot = WinbackCopyExperiment.resolve(variantKey: "unknown-variant")
        XCTAssertEqual(snapshot.variant, .control)
        XCTAssertFalse(snapshot.isFlagResolved)
    }

    /// super property 的 key 固定，改名会静默丢失实验数据。
    func testSuperPropertyKeyIsStable() {
        let resolved = WinbackCopyExperiment(variant: .access, isFlagResolved: true)
        XCTAssertEqual(resolved.superPropertyKey, "winback-save-copy-variant")
        XCTAssertEqual(resolved.superPropertyValue, "access")
        XCTAssertEqual(
            WinbackCopyExperiment(variant: .control, isFlagResolved: true).superPropertyValue,
            "control"
        )
    }

    /// 文案跟随传入的分组，不再各自读 flag。
    func testCopyFollowsProvidedVariant() {
        XCTAssertEqual(
            ProPaywallCopy.winbackSaveLabel(.yearlyDiscount, variant: .access),
            BSLocalization.text("现场与回忆保留")
        )
        XCTAssertEqual(
            ProPaywallCopy.winbackSaveLabel(.lifetimeDiscount, variant: .access),
            BSLocalization.text("一次解锁，永久保留")
        )
        XCTAssertEqual(
            ProPaywallCopy.winbackSaveLabel(.yearlyDiscount, variant: .control),
            BSLocalization.text("省 40%")
        )
        // 非挽留方案恒为空角标。
        XCTAssertEqual(ProPaywallCopy.winbackSaveLabel(.yearly, variant: .access), "")
        XCTAssertEqual(ProPaywallCopy.winbackSaveLabel(.lifetime, variant: .access), "")
    }

    /// 同一个快照下，文案与曝光分组必须一致。
    func testCopyAndExposureAgreeForSameSnapshot() {
        for snapshot in [
            WinbackCopyExperiment.resolve(variantKey: "access"),
            WinbackCopyExperiment.resolve(variantKey: "control")
        ] {
            let label = ProPaywallCopy.winbackSaveLabel(.yearlyDiscount, variant: snapshot.variant)
            switch snapshot.variant {
            case .access:
                XCTAssertEqual(label, BSLocalization.text("现场与回忆保留"))
                XCTAssertEqual(snapshot.superPropertyValue, "access")
            case .control:
                XCTAssertEqual(label, BSLocalization.text("省 40%"))
                XCTAssertEqual(snapshot.superPropertyValue, "control")
            }
        }
    }
}


/// PR #357 review: `$revenue` 的准入判定。商品标价不是收入：免费试用 / intro
/// 优惠会给 Pro 权益但当期没收钱，拿不到可信实收金额时必须不上报。
final class PurchaseRevenueTests: XCTestCase {
    private func paidProduct(amount: Decimal = 4.99, currency: String? = "USD") -> ProSubscriptionProduct {
        ProSubscriptionProduct(
            id: "com.doublewaterapps.beforeshow.pro.test",
            plan: .yearly,
            displayName: "Test",
            priceText: "$4.99/年",
            benefitCopy: [],
            isAvailable: true,
            priceAmount: amount,
            priceCurrency: currency
        )
    }

    /// store 真实返回价格的产品（Mock 默认 catalog 只给占位价）。
    private func pricedProduct() -> ProSubscriptionProduct {
        paidProduct()
    }



    /// store 返回的真实价格与货币是唯一上报来源。
    func testPaidPurchaseReportsListPriceWhenCharged() {
        let revenue = paidProduct().revenueIfCharged
        XCTAssertEqual(revenue?.amount, 4.99)
        XCTAssertEqual(revenue?.currency, "USD")
    }

    /// 试用 / intro：entitlement periodType 不是 normal → 无实收金额。
    func testTrialPeriodTypeHasNoRevenue() {
        for period in [PeriodType.trial, .intro] {
            XCTAssertNil(RevenueCatProSubscriptionStore.revenue(
                entitlementPeriodType: period,
                transactionPrice: nil,
                currencyCode: "USD"
            ))
        }
    }

    /// 拿不到 periodType 时保守不上报：宁可漏，不把试用记成正收入。
    func testUnknownPeriodTypeHasNoRevenue() {
        XCTAssertNil(RevenueCatProSubscriptionStore.revenue(
            entitlementPeriodType: nil,
            transactionPrice: nil,
            currencyCode: "USD"
        ))
    }

    /// 普通付费 + 交易实付金额 > 0 + 有货币才记。
    func testNormalPeriodTypeReportsRevenue() {
        XCTAssertEqual(
            RevenueCatProSubscriptionStore.revenue(
                entitlementPeriodType: .normal,
                transactionPrice: 4.99,
                currencyCode: "USD"
            ),
            ProPurchaseRevenue(amount: 4.99, currency: "USD")
        )
    }

    /// **普通计费周期但跟不到交易实付价格时不得回落到商品标价。**
    /// 优惠 / 促销使实付低于标价，而 `periodType == .normal` 只说明权益
    /// 在普通周期，不证明等于标价；拿标价填空会高报营收。
    func testMissingTransactionPriceHasNoRevenue() {
        XCTAssertNil(RevenueCatProSubscriptionStore.revenue(
            entitlementPeriodType: .normal,
            transactionPrice: nil,
            currencyCode: "USD"
        ))
    }

    /// 实付低于标价（折扣 / 促销）时按实付金额记。
    func testDiscountedTransactionPriceIsReportedAsIs() {
        XCTAssertEqual(
            RevenueCatProSubscriptionStore.revenue(
                entitlementPeriodType: .normal,
                transactionPrice: 2.99,
                currencyCode: "USD"
            ),
            ProPurchaseRevenue(amount: 2.99, currency: "USD")
        )
    }

    /// 实付为零（零元促销）不记。
    func testZeroTransactionPriceHasNoRevenue() {
        XCTAssertNil(RevenueCatProSubscriptionStore.revenue(
            entitlementPeriodType: .normal,
            transactionPrice: 0,
            currencyCode: "USD"
        ))
    }

    /// 缺货币不上报，避免金额被记成默认货币。
    func testMissingCurrencyHasNoRevenue() {
        XCTAssertNil(RevenueCatProSubscriptionStore.revenue(
            entitlementPeriodType: .normal,
            transactionPrice: 4.99,
            currencyCode: nil
        ))
    }


    /// catalog 占位价（isAvailable == false）不是收入来源。
    func testCatalogPlaceholderIsNotRevenue() {
        let placeholder = paidProduct().markingAvailable(false)
        XCTAssertFalse(placeholder.isAvailable)
        XCTAssertNil(placeholder.revenueIfCharged)
    }

    /// 成交带交易标识，`$revenue` 才能按交易去重。
    func testPurchaseOutcomeCarriesTransactionID() async throws {
        let store = MockProSubscriptionStore()
        let products = try await store.loadProducts()
        let purchased = try await store.purchase(productID: products[0].id)
        XCTAssertNotNil(purchased.transactionID)
    }

    /// Mock 模拟免费试用：权益生效但没有实收金额。
    func testTrialPurchaseHasEntitlementWithoutRevenue() async throws {
        let store = MockProSubscriptionStore(simulatedTrial: true)
        let products = try await store.loadProducts()
        let purchased = try await store.purchase(productID: products[0].id)

        XCTAssertTrue(purchased.isProActive, "试用也会给权益")
        XCTAssertNil(purchased.revenue, "试用不能按标价记收入")
    }

    /// 报不出交易实付价格时：权益生效，但不得把商品标价当实收。
    func testPurchaseWithoutTransactionPriceHasNoRevenue() async throws {
        let product = pricedProduct()
        let store = MockProSubscriptionStore(
            products: [product],
            simulatedMissingTransactionPrice: true
        )
        let purchased = try await store.purchase(productID: product.id)

        XCTAssertTrue(purchased.isProActive, "普通计费周期仍给权益")
        XCTAssertEqual(product.revenueIfCharged?.amount, 4.99, "商品标价确实存在")
        XCTAssertNil(purchased.revenue, "取不到实付金额时不得回落到标价")
    }

    /// 正常成交：权益 + 实收金额都在。
    func testPaidPurchaseHasEntitlementWithRevenue() async throws {
        let store = MockProSubscriptionStore(products: [pricedProduct()])
        let products = try await store.loadProducts()
        let purchased = try await store.purchase(productID: products[0].id)

        XCTAssertTrue(purchased.isProActive)
        XCTAssertEqual(purchased.revenue, ProPurchaseRevenue(amount: 4.99, currency: "USD"))
    }

    /// 试用与正常成交都给权益，区别只在本期收没收钱。
    func testTrialAndPaidDifferOnlyInRevenue() async throws {
        let product = pricedProduct()
        let trial = try await MockProSubscriptionStore(products: [product], simulatedTrial: true)
            .purchase(productID: product.id)
        let paid = try await MockProSubscriptionStore(products: [product])
            .purchase(productID: product.id)

        XCTAssertTrue(trial.entitlement.isProActive)
        XCTAssertTrue(paid.entitlement.isProActive)
        XCTAssertNil(trial.revenue)
        XCTAssertNotNil(paid.revenue)
    }
}

/// docs/observability/posthog-activation-goal.md 第 5 项：feature flag 驱动实验分组。
///
/// flag 未命中 / 关闭时（`variantKey` 返回 nil，测试环境下 SDK 未 setup），
/// 文案必须退回 control，即线上已审的「省 40%」。
final class WinbackCopyVariantTests: XCTestCase {
    func testControlCopyWhenFlagNotEvaluated() {
        XCTAssertEqual(ProPaywallCopy.winbackSaveLabel(.yearlyDiscount), BSLocalization.text("省 40%"))
        XCTAssertEqual(ProPaywallCopy.winbackSaveLabel(.lifetimeDiscount), BSLocalization.text("省 33%"))
    }

    /// 非挽留方案不论 flag 取何值都不给角标，行为与原来一致。
    func testStandardPlansHaveNoBadge() {
        XCTAssertEqual(ProPaywallCopy.winbackSaveLabel(.yearly), "")
        XCTAssertEqual(ProPaywallCopy.winbackSaveLabel(.lifetime), "")
    }

    /// flag key 是 PostHog 里的固定常量，改名会静默丢失实验数据。
    func testFlagKeysAreStable() {
        XCTAssertEqual(RemoteConfig.FlagKey.winbackSaveCopyVariant, "winback-save-copy-variant")
        XCTAssertEqual(RemoteConfig.WinbackSaveCopyVariant.control.rawValue, "control")
        XCTAssertEqual(RemoteConfig.WinbackSaveCopyVariant.access.rawValue, "access")
    }
}
