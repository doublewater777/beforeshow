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

    /// 插入遇到重复条目（并发竞争）时，已建立的那条就是躓家：
    /// 直接上报它，不生成也不覆盖。
    func testDuplicateItemKeepsExistingIdentity() {
        let outcome = AnalyticsInstallIDResolution.resolve(
            existing: nil,
            writeStatus: .succeeded("winner-id")
        )
        XCTAssertEqual(outcome.identifiedID, "winner-id")
        XCTAssertNil(outcome.valueToPersist)
    }

    /// 重复条目存在但重读失败（项被删除 / 读不到）时不得上报新值：
    /// 否则两个并发调用会拿到两个 Person 身份。
    func testDuplicateItemUnreadableYieldsNoIdentity() {
        let outcome = AnalyticsInstallIDResolution.resolve(existing: nil, writeStatus: .failed)
        XCTAssertNil(outcome.identifiedID)
        XCTAssertNil(outcome.valueToPersist)
    }

    /// 同一次竞争里输入的入参不会改变决策：已存在值始终优先。
    func testExistingAlwaysWinsOverGenerated() {
        XCTAssertEqual(
            AnalyticsInstallIDResolution.resolve(
                existing: "established",
                writeStatus: .succeeded("generated-id")
            ).identifiedID,
            "established"
        )
    }
}
