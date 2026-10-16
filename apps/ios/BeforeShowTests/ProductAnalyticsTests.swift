import XCTest
@testable import BeforeShow

/// docs/observability/product-analytics.md：北极星陪伴行为与公共属性。
final class ProductAnalyticsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    func testCoreActionsCarryFlagAndShowID() {
        let showID = UUID()
        let core: [AnalyticsEvent] = [
            .listenPlaybackStarted(source: .preview),
            .timetableSaved(showID: showID, performanceCount: 3, isNew: true),
            .memoryFragmentCreated(showID: showID, mediaCount: 0, phase: .live),
            .dispersalCeremonyCompleted(showID: showID, rating: nil, hasNote: false),
            .memoryCardShared(showID: showID, materialCount: 2),
            .appOpenedFrom(source: .widget, destination: "listen", feature: nil),
            .appOpenedFrom(source: .liveActivity, destination: "route", feature: nil)
        ]
        for event in core {
            XCTAssertEqual(event.properties["core_action"] as? Bool, true, event.name)
        }

        let other: [AnalyticsEvent] = [
            .showAdded(showID: showID, method: "manual", lifecycle: "future", isFirstShow: true, isFestival: false),
            .appOpenedFrom(source: .notification, destination: "listen", feature: .listen),
            .featureRecommendationShown(showID: showID, feature: .listen),
            .proPaywallViewed
        ]
        for event in other {
            XCTAssertNil(event.properties["core_action"], event.name)
        }
    }

    func testEventPayloads() {
        let showID = UUID()
        let added = AnalyticsEvent.showAdded(
            showID: showID, method: "link", lifecycle: "future", isFirstShow: true, isFestival: true
        ).properties
        XCTAssertEqual(added["show_id"] as? String, showID.uuidString)
        XCTAssertEqual(added["is_first_show"] as? Bool, true)
        XCTAssertEqual(added["is_festival"] as? Bool, true)

        let memory = AnalyticsEvent.memoryFragmentCreated(showID: showID, mediaCount: 2, phase: .after).properties
        XCTAssertEqual(memory["has_media"] as? Bool, true)
        XCTAssertEqual(memory["phase"] as? String, "after")

        let listen = AnalyticsEvent.listenPlaybackStarted(source: .fullCatalog)
        XCTAssertEqual(listen.name, "listen_playback_started")
        XCTAssertEqual(listen.properties["source"] as? String, "full")

        let tapped = AnalyticsEvent.featureRecommendationTapped(showID: showID, feature: .timetable, surface: .notification)
        XCTAssertEqual(tapped.properties["feature"] as? String, "timetable")
        XCTAssertEqual(tapped.properties["surface"] as? String, "notification")

        let rated = AnalyticsEvent.dispersalCeremonyCompleted(showID: showID, rating: 4, hasNote: true).properties
        XCTAssertEqual(rated["rating_value"] as? Int, 4)
        XCTAssertEqual(rated["has_rating"] as? Bool, true)
    }

    func testOnboardingInviteCarriesNoTokenOrShowName() {
        XCTAssertTrue(AnalyticsEvent.onboardingInviteAccepted.properties.isEmpty)
    }

    @MainActor
    func testContextResolvesCurrentShowPhase() throws {
        let now = date(day: 15, hour: 12)
        let future = try show(day: 25)
        let today = try show(day: 15, hour: 20)
        let live = try show(day: 15, hour: 11)
        let past = try show(day: 1)
        past.markEnded(at: date(day: 1, hour: 23))
        let shows = [future, today, live, past]

        let before = AnalyticsContext(shows: shows, currentShowID: future.id, isPro: true, hasWidget: false, now: now)
        XCTAssertEqual(before.phase, .before)
        XCTAssertEqual(before.daysUntil, 10)
        XCTAssertEqual(before.properties["current_show_id"] as? String, future.id.uuidString)
        XCTAssertEqual(before.properties["is_pro"] as? Bool, true)
        XCTAssertEqual(before.showCount, 4)
        XCTAssertEqual(before.footprintCount, 1)

        XCTAssertEqual(AnalyticsContext(shows: shows, currentShowID: today.id, isPro: false, hasWidget: false, now: now).phase, .showDay)
        XCTAssertEqual(AnalyticsContext(shows: shows, currentShowID: live.id, isPro: false, hasWidget: false, now: now).phase, .live)

        let none = AnalyticsContext(shows: shows, currentShowID: nil, isPro: false, hasWidget: true, now: now)
        XCTAssertEqual(none.phase, .none)
        XCTAssertNil(none.properties["current_show_id"])
        XCTAssertNil(none.properties["current_show_days_until"])
        XCTAssertEqual(none.properties["has_widget"] as? Bool, true)
        XCTAssertEqual(Set(none.properties.keys).subtracting(AnalyticsContext.keys), [])
    }

    private func show(day: Int, hour: Int = 20) throws -> Show {
        try Show(
            name: "现场",
            date: date(day: day, hour: 0),
            startTime: date(day: day, hour: hour),
            timeZoneIdentifier: "UTC"
        )
    }

    private func date(day: Int, hour: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: day, hour: hour).date!
    }
}
