import Foundation
import XCTest
@testable import BeforeShow

final class ListeningReminderSchedulingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testUncachedArtistGetsAnEveningReminderFromTheDayTheShowIsAdded() throws {
        let now = date("2026-10-11T10:00:00Z")
        let show = try Show(name: "秋夜", date: date("2026-10-15T20:00:00Z"),
                            startTime: date("2026-10-15T20:00:00Z"), createdAt: now)
        show.artists = [ArtistSlot(name: "B", avatarURL: nil)]
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now)
        let reminders = requests.filter { $0.milestone.rawValue == "listeningReminder" }
        XCTAssertEqual(reminders.map(\.fireDate), [date("2026-10-11T20:00:00Z")])
        XCTAssertEqual(reminders.first?.title, "秋夜")
        XCTAssertEqual(reminders.first?.body, BSLocalization.format("来听听%@的歌。", "B"))
        XCTAssertEqual(reminders.first?.userInfo["artistName"] as? String, "B")
        XCTAssertEqual(reminders.first?.destination, .listen)
    }
    func testSingleArtistStartsWithSingalongThenLatestAlbumThenFeaturedPlaylist() throws {
        let now = date("2026-10-01T10:00:00Z")
        let show = try Show(name: "秋夜", date: date("2026-10-15T20:00:00Z"),
                            startTime: date("2026-10-15T20:00:00Z"), createdAt: now)
        show.artists = [ArtistSlot(name: "B", avatarURL: nil, appleMusicArtistID: "b")]
        let roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B",
            albums: [.init(id: "album", title: "最新专辑")],
            featuredPlaylist: .init(id: "essentials", title: "B 精选"))],
            singalong: .init(id: "singalong", title: "大合唱"))
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now,
            scope: NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster))
            .filter { $0.milestone == .listeningReminder }
        XCTAssertEqual(Array(requests.prefix(3)).map { $0.userInfo["discID"] as? String },
                       ["singalong", "album", "essentials"])
        XCTAssertEqual(Array(requests.prefix(3)).map(\.fireDate),
                       [date("2026-10-01T20:00:00Z"), date("2026-10-02T20:00:00Z"), date("2026-10-03T20:00:00Z")])
        XCTAssertEqual(Set(requests.map(\.requestIdentifier)).count, requests.count)
        XCTAssertEqual(requests.first?.title, "秋夜")
        XCTAssertEqual(requests.first?.body, BSLocalization.text("收录了现场常演的热门歌，可以先熟悉一下。"))
        XCTAssertEqual(requests[2].body, BSLocalization.format("从这份精选歌单开始，认识一下%@。", "B"))
        XCTAssertEqual(requests[1].body, BSLocalization.format("听听%1$@的专辑《%2$@》。", "B", "最新专辑"))
    }

    func testFestivalRotatesArtistsAndInsertsACompilationAfterEveryTwo() throws {
        let now = date("2026-10-01T10:00:00Z")
        let show = try Show(name: "音乐节", date: date("2026-12-30T20:00:00Z"),
                            startTime: date("2026-12-30T20:00:00Z"), createdAt: now)
        let artists = ["a", "b", "c", "d"].map { id in
            ListeningReminderRoster.Artist(id: id, name: id,
                albums: [.init(id: id + "-new", title: id), .init(id: id + "-old", title: id)])
        }
        let roster = ListeningReminderRoster(artists: artists, isMultiArtist: true,
            singalong: .init(id: "sing", title: "大合唱"), latest: .init(id: "new", title: "新歌"),
            deepCuts: .init(id: "deep", title: "深挖"))
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now,
            scope: NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster))
            .filter { $0.milestone == .listeningReminder }
        XCTAssertEqual(Array(requests.prefix(11)).map { $0.userInfo["discID"] as? String },
            ["a-new", "b-new", "sing", "c-new", "d-new", "new", "a-old", "b-old", "deep", "c-old", "d-old"])
        XCTAssertEqual(requests[5].body, BSLocalization.text("听听参演艺人最近发行的新歌。"))
        XCTAssertEqual(requests[8].body, BSLocalization.text("热门曲目之外，这些作品也值得一听。"))
    }

    func testThreeIgnoredRemindersThinOutUntilListeningResumesAndTodayStaysQuiet() throws {
        let added = date("2026-10-01T10:00:00Z")
        let show = try Show(name: "秋夜", date: date("2026-10-15T20:00:00Z"),
                            startTime: date("2026-10-15T20:00:00Z"), createdAt: added)
        var roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B",
            albums: (1...30).map { .init(id: "album-\($0)", title: "唱片 \($0)") })])
        func evenings(_ now: Date) -> [Date] {
            LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now,
                scope: NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster))
                .filter { $0.milestone == .listeningReminder }.map(\.fireDate)
        }
        XCTAssertEqual(evenings(added), [1, 2, 3, 6, 9, 12].map {
            date(String(format: "2026-10-%02dT20:00:00Z", $0))
        })
        roster.lastListenedAt = date("2026-10-04T11:00:00Z")
        XCTAssertEqual(evenings(date("2026-10-04T12:00:00Z")), [5, 6, 7, 9, 12].map {
            date(String(format: "2026-10-%02dT20:00:00Z", $0))
        })
    }

    func testPastNodesKeepTheirPlaceCompletedDiscsAreSkippedAndExhaustionRepeatsEveryOtherDay() throws {
        let show = try Show(name: "秋夜", date: date("2026-10-15T20:00:00Z"),
            startTime: date("2026-10-15T20:00:00Z"), createdAt: date("2026-10-01T10:00:00Z"))
        let roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B",
            albums: [.init(id: "new", title: "新专辑"), .init(id: "old", title: "旧专辑")])],
            singalong: .init(id: "sing", title: "大合唱"), completedDiscIDs: ["new"])
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(
            for: show, now: date("2026-10-02T10:00:00Z"),
            scope: NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster))
            .filter { $0.milestone == .listeningReminder }
        XCTAssertEqual(Array(requests.prefix(2)).map { $0.userInfo["discID"] as? String }, ["old", "sing"])
        XCTAssertEqual(Array(requests.prefix(2)).map(\.fireDate),
                       [date("2026-10-02T20:00:00Z"), date("2026-10-04T20:00:00Z")])
        XCTAssertEqual(requests.dropFirst().first?.body, BSLocalization.text("离现场越来越近了，再听听这份热门歌单吧。"))
    }

    func testNotificationRecommendationsLeaveListeningToItsOwnRhythm() throws {
        for addedDay in [1, 10] {
            let added = date(String(format: "2026-10-%02dT10:00:00Z", addedDay))
            let show = try Show(name: "演唱会", date: date("2026-10-15T20:00:00Z"),
                                startTime: date("2026-10-15T20:00:00Z"), createdAt: added)
            var scope = NotificationScheduleScope.all
            scope.recommendations.used = [.companion]
            let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: added, scope: scope)
            XCTAssertFalse(requests.contains { $0.feature == .listen })
            XCTAssertFalse(requests.contains { $0.milestone == .sevenDaysBefore || $0.milestone == .threeDaysBefore })
        }
        XCTAssertEqual(FeatureRecommendationPolicy.candidate(
            from: FeatureRecommendationSlot.cardNearBefore.chain(isFestival: false, hasFutureShow: false),
            context: FeatureRecommendationContext()), .listen)
    }

    func testFinalRemindersShareExistingNodesAndKeepTheShowDayBodyOnTheRoute() throws {
        let now = date("2026-10-13T10:00:00Z")
        let show = try Show(name: "秋夜", date: date("2026-10-15T20:00:00Z"),
                            startTime: date("2026-10-15T20:00:00Z"), createdAt: now)
        for (multi, wanted, expectedEvening, expectedRoad) in [
            (false, false, "sing", "rehearsal"), (true, true, "wanted", "wanted"), (true, false, "sing", "sing")
        ] {
            let roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B")], isMultiArtist: multi,
                singalong: .init(id: "sing", title: "大合唱"),
                wanted: wanted ? .init(id: "wanted", title: "想看") : nil,
                rehearsal: multi ? nil : .init(id: "rehearsal", title: "彩排"))
            let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now,
                scope: NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster))
            let evening = try XCTUnwrap(requests.first { $0.milestone == .oneDayBefore })
            let road = try XCTUnwrap(requests.first { $0.milestone == .showDay })
            XCTAssertEqual(evening.userInfo["discID"] as? String, expectedEvening)
            XCTAssertEqual(road.userInfo["discID"] as? String, expectedRoad)
            let invitation = multi && wanted
                ? BSLocalization.text("听听你标记的那些艺人吧。")
                : BSLocalization.text("挑几首常演的热门歌预热一下。")
            let expectedEveningBody = Bundle.main.preferredLocalizations.first == "en"
                ? (multi && wanted ? "Starts tomorrow. Listen to the artists you saved."
                    : "Starts tomorrow. Warm up with a few popular live favorites.")
                : BSLocalization.text("明天开场。") + invitation
            XCTAssertEqual(evening.body, expectedEveningBody)
            XCTAssertEqual(evening.destination, .listen)
            XCTAssertEqual(road.destination, .route)
            XCTAssertEqual(road.makeNotificationRequest().content.categoryIdentifier, "listeningReminder")
            XCTAssertTrue(road.body.hasSuffix(BSLocalization.text("。还有 3 小时，准备出门，路上让这些歌陪你出发。")))
            XCTAssertFalse(requests.contains { $0.milestone == .listeningReminder && $0.fireDate >= date("2026-10-14T00:00:00Z") })
        }
    }

    func testImminentOpeningKeepsOnlyTheRouteWithoutAPlaybackAction() throws {
        let now = date("2026-10-15T19:00:00Z")
        let show = try Show(name: "秋夜", date: date("2026-10-15T20:00:00Z"),
                            startTime: date("2026-10-15T20:00:00Z"), createdAt: now)
        let roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B")],
            singalong: .init(id: "sing", title: "大合唱"),
            rehearsal: .init(id: "rehearsal", title: "彩排"))
        let requests = LocalNotificationScheduler(calendar: calendar).futureRequests(for: show, now: now,
            scope: NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster))
        let opening = try XCTUnwrap(requests.first { $0.milestone == .showDay })
        XCTAssertEqual(opening.destination, .route)
        XCTAssertNil(opening.userInfo["discID"])
        XCTAssertNotEqual(opening.makeNotificationRequest().content.categoryIdentifier, "listeningReminder")
        XCTAssertFalse(opening.body.contains("彩排"))
    }

    func testPassingAFeatureRecommendationDayDoesNotShiftFutureDiscs() throws {
        let show = try Show(name: "演唱会", date: date("2026-10-15T20:00:00Z"),
            startTime: date("2026-10-15T20:00:00Z"), createdAt: date("2026-10-01T10:00:00Z"))
        let roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B",
            albums: (1...30).map { .init(id: "album-\($0)", title: "唱片 \($0)") })],
            lastListenedAt: date("2026-10-07T12:00:00Z"))
        let scope = NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster)
        let scheduler = LocalNotificationScheduler(calendar: calendar)
        let later = date("2026-10-09T10:00:00Z")
        let earlierPlan = scheduler.futureRequests(for: show, now: date("2026-10-07T13:00:00Z"), scope: scope)
            .filter { $0.milestone == .listeningReminder && $0.fireDate > later }
        let laterPlan = scheduler.futureRequests(for: show, now: later, scope: scope)
            .filter { $0.milestone == .listeningReminder }
        XCTAssertEqual(laterPlan, earlierPlan)
    }

    func testCadenceBoundariesAndStableIdentifiersKeepEventLocalEightPMAcrossDST() throws {
        let showDate = date("2026-12-02T04:00:00Z")
        let roster = ListeningReminderRoster(artists: [.init(id: "b", name: "B",
            albums: (1...100).map { .init(id: "album-\($0)", title: "唱片 \($0)") })])
        let examples: [(String, [String])] = [
            ("2026-09-01T17:00:00Z", ["2026-09-06T03:00:00Z", "2026-09-13T03:00:00Z", "2026-09-20T03:00:00Z"]),
            ("2026-10-31T17:00:00Z", ["2026-11-01T03:00:00Z", "2026-11-02T04:00:00Z", "2026-11-05T04:00:00Z"]),
            ("2026-11-16T18:00:00Z", ["2026-11-17T04:00:00Z", "2026-11-18T04:00:00Z", "2026-11-19T04:00:00Z"]),
            ("2026-11-17T05:00:00Z", ["2026-11-18T04:00:00Z", "2026-11-19T04:00:00Z", "2026-11-20T04:00:00Z"]),
            ("2026-11-29T18:00:00Z", ["2026-11-30T04:00:00Z"])
        ]
        for (addedAt, expected) in examples {
            let now = date(addedAt)
            let show = try Show(name: "秋夜", date: showDate, startTime: showDate, createdAt: now)
            show.timeZoneIdentifier = "America/Los_Angeles"
            let scope = NotificationScheduleScope(includesAllMilestones: true, listeningRoster: roster)
            let scheduler = LocalNotificationScheduler(calendar: calendar)
            let requests = scheduler.futureRequests(for: show, now: now, scope: scope)
                .filter { $0.milestone == .listeningReminder }
            XCTAssertEqual(Array(requests.prefix(3)).map(\.fireDate), expected.map(date), addedAt)
            XCTAssertEqual(requests.map(\.requestIdentifier),
                scheduler.futureRequests(for: show, now: now.addingTimeInterval(1), scope: scope)
                    .filter { $0.milestone == .listeningReminder }.map(\.requestIdentifier))
        }
    }

}
