import XCTest
@testable import BeforeShow

/// docs/observability/posthog-activation-goal.md：身份与营收埋点。
final class AnalyticsIdentityTests: XCTestCase {
    /// 安装 ID 每次读取都应返回同一个值（Keychain 持久化，非随机）。
    func testInstallIDIsStable() {
        let first = AnalyticsInstallID.current()
        let second = AnalyticsInstallID.current()
        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
    }
}

/// Keychain 写入失败时不能把临时随机 ID 当成稳定身份（PR #357 review P1）。
final class AnalyticsInstallIDResolutionTests: XCTestCase {
    /// 已持久化 ID 优先：不重新生成，也不把它当成待持久化值。
    func testPersistedIDWinsWithoutWriting() {
        let outcome = AnalyticsInstallIDResolution.resolve(
            existing: "existing-id",
            writeStatus: .succeeded("generated-id")
        )
        XCTAssertEqual(outcome.identifiedID, "existing-id")
        XCTAssertNil(outcome.valueToPersist)
    }

    /// 写入成功：返回写入的那个 ID。
    func testWrittenIDIsUsedAsIdentity() {
        let outcome = AnalyticsInstallIDResolution.resolve(
            existing: nil,
            writeStatus: .succeeded("generated-id")
        )
        XCTAssertEqual(outcome.identifiedID, "generated-id")
    }

    /// 写入失败：不返回临时 ID（否则同一装会被切成多个 Person）。
    func testWriteFailureYieldsNoIdentity() {
        let outcome = AnalyticsInstallIDResolution.resolve(existing: nil, writeStatus: .failed)
        XCTAssertNil(outcome.identifiedID)
        XCTAssertNil(outcome.valueToPersist)
    }

    /// 读回空串等同不存在，不能当成身份上报。
    func testEmptyPersistedIDIsNotUsedAsIdentity() {
        let outcome = AnalyticsInstallIDResolution.resolve(
            existing: "",
            writeStatus: .succeeded("generated-id")
        )
        XCTAssertEqual(outcome.identifiedID, "generated-id")
    }
}
