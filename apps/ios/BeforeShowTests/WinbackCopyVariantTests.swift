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

/// PR #357 review P1：`$revenue` 只在「真实成交且金额为正」时上报。
final class RevenueEventPolicyTests: XCTestCase {
    private func product(_ plan: ProSubscriptionPlan, amount: Decimal?, currency: String?) -> ProSubscriptionProduct {
        ProSubscriptionProduct(
            id: "com.doublewaterapps.beforeshow.pro.test",
            plan: plan,
            displayName: "Test",
            priceText: "$4.99/年",
            benefitCopy: [],
            isAvailable: true,
            priceAmount: amount,
            priceCurrency: currency
        )
    }

    /// 试用 / 已拥有 / 恢复：权益不因本次购买首次转为 Pro 时不产生营收。
    func testRevenueOnlyWhenPurchaseActivatesPro() {
        let active: ProEntitlementState = .active(productID: "p", expirationDate: nil)
        let free: ProEntitlementState = .free

        XCTAssertTrue(RevenueEventPolicy.shouldCaptureRevenue(entitlement: active, previous: .free))
        // 免费试用：购买完成后仍可能是 free（首次试用未激活付费权益）。
        XCTAssertFalse(RevenueEventPolicy.shouldCaptureRevenue(entitlement: free, previous: .free))
        // 已拥有 Pro 再购买（理论上不会被 UI 走到）不重复计营收。
        XCTAssertFalse(RevenueEventPolicy.shouldCaptureRevenue(entitlement: active, previous: active))
    }

    /// 零金额（免费试用 / 免费恢复）不记为营收。
    func testZeroAmountIsNotRevenue() {
        let freeTrial = product(.yearly, amount: 0, currency: "USD")
        XCTAssertEqual(RevenueEventPolicy.revenueAmount(freeTrial), nil)
    }

    /// catalog 占位价（isAvailable == false）不当作营收上报。
    func testUnavailableCatalogPlaceholderIsNotRevenue() {
        let placeholder = product(.yearly, amount: 4.99, currency: nil)
            .markingAvailable(false)
        XCTAssertFalse(placeholder.isAvailable)
        XCTAssertNil(RevenueEventPolicy.revenueAmount(placeholder))
    }

    /// 有价格与货币时给出 (amount, currency)。
    func testAmountAndCurrencyReturnedTogether() {
        let real = product(.yearly, amount: 4.99, currency: "USD")
        XCTAssertEqual(RevenueEventPolicy.revenueAmount(real), 4.99)
        XCTAssertEqual(RevenueEventPolicy.revenueCurrency(real), "USD")
    }

    /// 成交必须带交易标识，`$revenue` 才能按交易去重。
    func testPurchaseOutcomeCarriesTransactionID() async throws {
        let store = MockProSubscriptionStore()
        let products = try await store.loadProducts()
        let purchased = try await store.purchase(productID: products[0].id)
        XCTAssertNotNil(purchased.transactionID)
    }

    /// 币种缺失时不上报，避免把金额记成默认货币。
    func testMissingCurrencyBlocksRevenue() {
        let noCurrency = product(.yearly, amount: 4.99, currency: nil)
        XCTAssertNil(RevenueEventPolicy.revenueCurrency(noCurrency))
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
