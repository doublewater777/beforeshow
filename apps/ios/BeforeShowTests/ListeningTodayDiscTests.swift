import UserNotifications
import XCTest
@testable import BeforeShow

final class ListeningTodayDiscTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let showID = UUID()
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "TodayDisc.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSameShowAndDayIsStable() throws {
        let pool = discs(8)
        let morning = day(7, hour: 8)
        let first = try XCTUnwrap(pick(pool, on: morning))
        for hour in [9, 13, 23] {
            XCTAssertEqual(pick(pool, on: day(7, hour: hour))?.id, first.id)
        }
        // Growing pool and listening to it later the same day keep the disc.
        let heard = Set(first.tracks.map(\.id))
        XCTAssertEqual(pick(pool + discs(4, prefix: "late"), heard: heard, on: day(7, hour: 22))?.id, first.id)
    }

    func testNextDayMovesToAnotherDisc() throws {
        let pool = discs(8)
        let today = try XCTUnwrap(pick(pool, on: day(7, hour: 9)))
        let tomorrow = try XCTUnwrap(pick(pool, on: day(8, hour: 9)))
        XCTAssertNotEqual(today.id, tomorrow.id)
    }

    func testPrefersDiscsNotFullyHeard() throws {
        let pool = discs(4)
        let heard = Set(pool.dropLast().flatMap { $0.tracks.map(\.id) })
        XCTAssertEqual(pick(pool, heard: heard, on: day(7, hour: 9))?.id, pool.last?.id)
    }

    func testShowSwitchFollowsTheNewShowPool() throws {
        let poolA = discs(5, prefix: "a")
        let poolB = discs(5, prefix: "b")
        _ = pick(poolA, on: day(7, hour: 9))
        let other = ListeningTodayDiscPolicy.disc(
            showID: UUID(), candidates: poolB, heardSongIDs: [], reminderDiscID: nil,
            on: day(7, hour: 10), calendar: calendar, defaults: defaults)
        XCTAssertTrue(poolB.contains { $0.id == other?.id })
    }

    func testReminderDiscWins() throws {
        let pool = discs(6)
        let picked = try XCTUnwrap(pick(pool, on: day(7, hour: 9)))
        let reminder = try XCTUnwrap(pool.first { $0.id != picked.id })
        XCTAssertEqual(pick(pool, reminder: reminder.id, on: day(7, hour: 10))?.id, reminder.id)
        // The day keeps the reminder disc once the notification is gone.
        XCTAssertEqual(pick(pool, on: day(7, hour: 21))?.id, reminder.id)
        // A reminder outside the pool is ignored.
        XCTAssertNotNil(pick(pool, reminder: "missing", on: day(9, hour: 9)))
    }

    func testDoesNotTouchPickDrawsOrRackHeads() throws {
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: ListeningDiscPickPolicy.showScopeKey,
                                           discID: "d1", defaults: defaults)
        let before = pickAndRackKeys()
        _ = pick(discs(5), on: day(7, hour: 9))
        _ = pick(discs(5), on: day(8, hour: 9))
        XCTAssertEqual(pickAndRackKeys(), before)
    }

    func testEmptyPoolHasNoDisc() {
        XCTAssertNil(pick([], on: day(7, hour: 9)))
        let empty = ListeningDisc(id: "e", title: "e", artworkURL: nil, tracks: [], origin: .album)
        XCTAssertNil(pick([empty], on: day(7, hour: 9)))
    }

    func testReminderDiscsByLocalDay() throws {
        let fire = day(7, hour: 20)
        let content = UNMutableNotificationContent()
        content.userInfo = NotificationDeepLink(showID: showID, destination: .listen, discID: "album-9").userInfo
        let mine = UNNotificationRequest(
            identifier: "\(showID.uuidString).listeningReminder.\(Int(fire.timeIntervalSince1970))",
            content: content, trigger: nil)
        let other = UNNotificationRequest(
            identifier: "\(UUID().uuidString).listeningReminder.\(Int(fire.timeIntervalSince1970))",
            content: content, trigger: nil)
        let byDay = ListeningReminderDayDiscs.discIDsByDay(showID: showID, requests: [mine, other], calendar: calendar)
        XCTAssertEqual(byDay, [ListeningDailyFeaturedDiscPolicy.dayKey(for: fire, calendar: calendar): "album-9"])
    }

    // MARK: - Helpers

    private func pick(_ pool: [ListeningDisc], heard: Set<String> = [], reminder: String? = nil,
                      on date: Date) -> ListeningDisc? {
        ListeningTodayDiscPolicy.disc(showID: showID, candidates: pool, heardSongIDs: heard,
                                      reminderDiscID: reminder, on: date, calendar: calendar, defaults: defaults)
    }

    private func pickAndRackKeys() -> [String: Data] {
        defaults.dictionaryRepresentation().reduce(into: [:]) { result, entry in
            guard entry.key.hasPrefix("listening.discPick.") || entry.key.hasPrefix("listening.dailyFeatured.") else { return }
            result[entry.key] = entry.value as? Data
        }
    }

    private func day(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func discs(_ count: Int, prefix: String = "d") -> [ListeningDisc] {
        (0..<count).map { index in
            let id = "\(prefix)\(index)"
            return ListeningDisc(
                id: id, title: id, artworkURL: URL(string: "https://example.com/\(id).png"),
                tracks: ["\(id)-1", "\(id)-2"].map {
                    ListeningDiscTrack(CatalogSong(appleMusicSongID: $0, title: $0, artistName: "Artist"))
                },
                origin: .album
            )
        }
    }
}
