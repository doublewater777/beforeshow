import XCTest
@testable import BeforeShow

/// 散场后首页揭晓这场解锁的数字唱片和徽章（ADR 0050）。
@MainActor
final class ShowUnlockRevealTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func show(_ dayOffset: Int, city: String) throws -> Show {
        let start = base.addingTimeInterval(TimeInterval(dayOffset) * day)
        return try Show(name: "现场 \(dayOffset)", date: start, startTime: start, endTime: start.addingTimeInterval(7_200), city: city)
    }

    private func unlocks(for show: Show, in shows: [Show], now: Date) -> ShowUnlocks {
        ShowUnlockReveal.unlocks(for: show, shows: shows, memories: [], merch: [], fragments: [], assets: [], now: now)
    }

    func testThirdCityUnlocksItsRecordAndTheCitiesBadge() throws {
        let shows = [try show(0, city: "上海"), try show(10, city: "北京"), try show(20, city: "杭州")]
        let tonight = shows[2]
        let result = unlocks(for: tonight, in: shows, now: tonight.date.addingTimeInterval(4 * 3_600))

        XCTAssertEqual(result.record?.number, 3)
        XCTAssertEqual(result.badges.map(\.family), [.cities])
        XCTAssertEqual(result.badges.first?.tier, 1)
    }

    func testRepeatCityGivesOnlyTheRecord() throws {
        let shows = [try show(0, city: "上海"), try show(10, city: "上海")]
        let tonight = shows[1]
        let result = unlocks(for: tonight, in: shows, now: tonight.date.addingTimeInterval(4 * 3_600))

        XCTAssertEqual(result.record?.number, 2)
        XCTAssertFalse(result.badges.contains { $0.family == .cities })
    }

    func testShowNumberFollowsTheArchiveOrderEvenPastTheLastRecord() throws {
        let shows = try (0..<51).map { try show($0 * 2, city: "上海") }
        let tonight = shows[50]
        let result = unlocks(for: tonight, in: shows, now: tonight.date.addingTimeInterval(4 * 3_600))

        XCTAssertEqual(result.showNumber, 51)
        XCTAssertNil(result.record)
    }

    func testEndedHeadlineCarriesTheShowNumber() {
        XCTAssertEqual(HomeCountdownLockup.endedHeadline(showNumber: 7), BSLocalization.format("第 %lld 场，结束了", 7))
        XCTAssertEqual(HomeCountdownLockup.endedHeadline(showNumber: nil), BSLocalization.text("这一场结束了"))
    }

    func testShowNotYetOverUnlocksNothing() throws {
        let tonight = try show(0, city: "上海")
        let result = unlocks(for: tonight, in: [tonight], now: tonight.date.addingTimeInterval(-3_600))
        XCTAssertTrue(result.isEmpty)
    }

    func testRevealIsShownOncePerShow() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ShowUnlockRevealTests"))
        defaults.removePersistentDomain(forName: "ShowUnlockRevealTests")
        let store = ShowUnlockRevealStore(defaults: defaults)
        let id = UUID()
        XCTAssertFalse(store.hasShown(id))
        store.markShown(id)
        XCTAssertTrue(store.hasShown(id))
        XCTAssertFalse(store.hasShown(UUID()))
    }
}
