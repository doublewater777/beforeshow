import XCTest
@testable import BeforeShow

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
