import XCTest
@testable import BeforeShow

/// docs/observability/posthog-activation-goal.md：身份与营收埋点。
final class AnalyticsIdentityTests: XCTestCase {
    /// 安装 ID 每次读取都应返回同一个值（Keychain 持久化，非随机）。
    func testInstallIDIsStable() {
        let first = AnalyticsInstallID.current()
        let second = AnalyticsInstallID.current()
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }
}
