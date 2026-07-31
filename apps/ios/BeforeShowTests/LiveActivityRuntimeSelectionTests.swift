import Foundation
import XCTest
@testable import BeforeShow

final class LiveActivityRuntimeSelectionTests: XCTestCase {
    private func makeState(
        name: String = "测试现场",
        startOffset: TimeInterval = 0
    ) -> ShowLiveActivityAttributes.ContentState {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + startOffset)
        return ShowLiveActivityAttributes.ContentState(
            showName: name,
            city: "上海",
            venueName: "测试场馆",
            startDate: start,
            endDate: start.addingTimeInterval(4 * 3_600),
            coverImageFilename: nil
        )
    }

    func testPendingKeeperChoosesOnlyOneOfDuplicateExactMatches() {
        let desired = makeState()
        let records = [
            LiveActivityRuntimeRecord(
                id: "pending-1",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
            LiveActivityRuntimeRecord(
                id: "pending-2",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
            LiveActivityRuntimeRecord(
                id: "other-show",
                showID: "show-2",
                isPending: true,
                state: desired
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.pendingKeeperID(
                in: records,
                showID: "show-1",
                state: desired
            ),
            "pending-1"
        )
    }

    func testPendingKeeperReturnsNilWhenOnlyStalePendingExists() {
        let desired = makeState()
        let stale = makeState(startOffset: 3_600)
        let records = [
            LiveActivityRuntimeRecord(
                id: "stale-pending",
                showID: "show-1",
                isPending: true,
                state: stale
            ),
            LiveActivityRuntimeRecord(
                id: "active-exact",
                showID: "show-1",
                isPending: false,
                state: desired
            ),
        ]

        XCTAssertNil(
            LiveActivityRuntimeSelection.pendingKeeperID(
                in: records,
                showID: "show-1",
                state: desired
            )
        )
    }

    func testDuplicateKeeperPrefersExactActiveOverExactPending() {
        let desired = makeState()
        let records = [
            LiveActivityRuntimeRecord(
                id: "pending-exact",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
            LiveActivityRuntimeRecord(
                id: "active-exact",
                showID: "show-1",
                isPending: false,
                state: desired
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.duplicateKeeperID(
                in: records,
                showID: "show-1",
                preferredState: desired
            ),
            "active-exact"
        )
    }

    func testDuplicateKeeperPrefersExactPendingOverStaleActive() {
        let desired = makeState()
        let stale = makeState(startOffset: 3_600)
        let records = [
            LiveActivityRuntimeRecord(
                id: "active-stale",
                showID: "show-1",
                isPending: false,
                state: stale
            ),
            LiveActivityRuntimeRecord(
                id: "pending-exact",
                showID: "show-1",
                isPending: true,
                state: desired
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.duplicateKeeperID(
                in: records,
                showID: "show-1",
                preferredState: desired
            ),
            "pending-exact"
        )
    }

    func testDuplicateKeeperFallsBackToFirstMatchingShow() {
        let first = makeState(name: "旧内容")
        let second = makeState(name: "另一旧内容")
        let records = [
            LiveActivityRuntimeRecord(
                id: "other-show",
                showID: "show-2",
                isPending: false,
                state: first
            ),
            LiveActivityRuntimeRecord(
                id: "first-show-1",
                showID: "show-1",
                isPending: false,
                state: first
            ),
            LiveActivityRuntimeRecord(
                id: "second-show-1",
                showID: "show-1",
                isPending: true,
                state: second
            ),
        ]

        XCTAssertEqual(
            LiveActivityRuntimeSelection.duplicateKeeperID(
                in: records,
                showID: "show-1",
                preferredState: makeState(name: "不存在")
            ),
            "first-show-1"
        )
    }
}
