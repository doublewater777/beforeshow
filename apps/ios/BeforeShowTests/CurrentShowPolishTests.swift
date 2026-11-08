import XCTest
@testable import BeforeShow

final class CurrentShowPolishTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    // MARK: Declared end

    func testFilledEndTimeEndsTheShowWithoutAsking() throws {
        let end = start.addingTimeInterval(3 * 3_600)
        let show = try Show(name: "Club", date: start, startTime: start, endTime: end)
        XCTAssertNil(CurrentShowEndPolicy.declaredEnd(for: show, now: end.addingTimeInterval(-60)))
        XCTAssertEqual(CurrentShowEndPolicy.declaredEnd(for: show, now: end.addingTimeInterval(60)), end)

        show.markEnded(at: end.addingTimeInterval(-600))
        XCTAssertNil(CurrentShowEndPolicy.declaredEnd(for: show, now: end.addingTimeInterval(60)))
    }

    func testEstimatedEndStillAsks() throws {
        let show = try Show(name: "No end", date: start, startTime: start)
        XCTAssertNil(CurrentShowEndPolicy.declaredEnd(for: show, now: start.addingTimeInterval(10 * 3_600)))
    }

    // MARK: Post-show primary

    func testPostShowPrimaryIsTheDispersalReview() throws {
        let end = start.addingTimeInterval(3 * 3_600)
        let show = try Show(name: "Club", date: start, startTime: start, endTime: end)
        show.markEnded(at: end)
        let now = end.addingTimeInterval(3_600)
        let state = CurrentShowTimeState(show: show, now: now)
        func primary(completed: Bool) -> HomeCountdownLockup.PrimaryAction? {
            HomeCountdownLockup.primaryAction(
                phase: HomeShowPhase(timeState: state, now: now), timeState: state,
                hasConfirmedEnd: true, hasEndHandler: false, hasCompletedDispersal: completed,
                recommendation: .memoryFragments
            )
        }
        XCTAssertEqual(primary(completed: false), .dispersal(completed: false))
        XCTAssertEqual(primary(completed: true), .dispersal(completed: true))
        XCTAssertFalse(FeatureRecommendationSlot.cardPostShow.chain(isFestival: true, hasFutureShow: true).contains(.memoryFragments))
        XCTAssertEqual(
            CurrentShowQuickAction.deduplicated([.dispersal(completed: true), .timetable], primaryAction: .dispersal(completed: true)),
            [.timetable]
        )
    }

    // MARK: Header chip

    func testHeaderChipOnlyForMultiDayFestivals() {
        XCTAssertNil(CurrentShowHomeHeader.chip(for: .active, dayIndex: 0, dayCount: 1))
        XCTAssertNil(CurrentShowHomeHeader.chip(for: .dayEnded(nextDayStartsAt: nil), dayIndex: 0, dayCount: 1))
        XCTAssertNil(CurrentShowHomeHeader.chip(for: .fullyEnded, dayIndex: 1, dayCount: 2))
        XCTAssertNil(CurrentShowHomeHeader.chip(for: .upcoming(firstStartsAt: start), dayIndex: 0, dayCount: 2))
        XCTAssertEqual(CurrentShowHomeHeader.chip(for: .active, dayIndex: 1, dayCount: 3)?.text, BSLocalization.format("第%d天", 2))
        XCTAssertNotNil(CurrentShowHomeHeader.chip(for: .dayEnded(nextDayStartsAt: nil), dayIndex: 0, dayCount: 2))
    }

    // MARK: Weather strip

    func testWeatherStripOpensOnNowAtTheShow() {
        let hours = (0..<24).map { start.addingTimeInterval(TimeInterval($0) * 3_600) }
        let band = 18...22
        XCTAssertEqual(ShowWeatherDays.leadIndex(hours: hours, band: band, now: start.addingTimeInterval(20.5 * 3_600)), 19)
        XCTAssertEqual(ShowWeatherDays.currentIndex(hours: hours, now: start.addingTimeInterval(20.5 * 3_600)), 20)
        XCTAssertEqual(ShowWeatherDays.leadIndex(hours: hours, band: band, now: start.addingTimeInterval(-86_400)), 16)
        XCTAssertNil(ShowWeatherDays.currentIndex(hours: hours, now: start.addingTimeInterval(-86_400)))
    }

    // MARK: Timetable ↔ lineup identity

    func testTimetableSetsReuseTheLineupMatch() {
        let lineup = [
            ArtistSlot(name: "黄子弘凡", avatarURL: nil, appleMusicArtistID: "1"),
            ArtistSlot(name: "回春丹乐队", avatarURL: nil, appleMusicArtistID: "2"),
            ArtistSlot(name: "奔赴少年CIIU", avatarURL: nil, appleMusicArtistID: "3"),
            ArtistSlot(name: "Unlinked", avatarURL: nil),
        ]
        XCTAssertEqual(TimetableLineupIdentity.slot(for: "奔赴少年CIIU", in: lineup)?.appleMusicArtistID, "3")
        XCTAssertEqual(TimetableLineupIdentity.slot(for: "黄子弘凡 60min限定舞台", in: lineup)?.appleMusicArtistID, "1")
        XCTAssertEqual(TimetableLineupIdentity.slot(for: "回春丹", in: lineup)?.appleMusicArtistID, "2")
        XCTAssertNil(TimetableLineupIdentity.slot(for: "Unlinked", in: lineup))
        XCTAssertNil(TimetableLineupIdentity.slot(for: "春浪岛", in: lineup))

        let ambiguous = [
            ArtistSlot(name: "Moon A", avatarURL: nil, appleMusicArtistID: "a"),
            ArtistSlot(name: "Moon B", avatarURL: nil, appleMusicArtistID: "b"),
        ]
        XCTAssertNil(TimetableLineupIdentity.slot(for: "Moon", in: ambiguous))
    }

    func testRematchInListenMovesTimetableSets() throws {
        let day = Date(timeIntervalSince1970: 1_790_956_800)
        let show = try Show(name: "Fest", date: day, startTime: day.addingTimeInterval(20 * 3_600))
        show.artists = [ArtistSlot(name: "回春丹", avatarURL: nil)]
        let set = try TimetablePerformance(artistName: "回春丹", startsAt: day.addingTimeInterval(20 * 3_600), endsAt: day.addingTimeInterval(21 * 3_600))
        let other = try TimetablePerformance(artistName: "野孩子", startsAt: day.addingTimeInterval(21 * 3_600), endsAt: day.addingTimeInterval(22 * 3_600))
        show.timetable = try Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [TimetableDay(date: day, stages: [TimetableStage(name: "Main", performances: [set, other])])])

        show.relinkArtist(at: 0, to: RecognizedArtist(id: "42", canonicalName: "回春丹乐队", avatarURL: nil, appleMusicURL: nil))

        XCTAssertEqual(show.artists.first?.appleMusicArtistID, "42")
        XCTAssertEqual(set.appleMusicArtistID, "42")
        XCTAssertEqual(set.artistName, "回春丹")
        XCTAssertNil(other.appleMusicArtistID)
    }
}
