import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class DeparturePlanSessionTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testBootstrapOriginPrefersSavedPlanOverSavedOrigin() throws {
        let show = try makeShow()
        let plan = RoundTripPlan(showID: show.id)
        plan.departureOrigin = "本场出发地"
        let saved = SavedOrigin(name: "家", addressText: "常用出发地")
        let session = DeparturePlanSession(show: show, calendar: calendar)

        XCTAssertEqual(session.resolvedOrigin(plan: plan, savedOrigin: saved), "本场出发地")
        XCTAssertEqual(session.resolvedOrigin(plan: nil, savedOrigin: saved), "常用出发地")
        XCTAssertEqual(session.resolvedOrigin(plan: nil, savedOrigin: nil), "")
    }

    func testDefaultTargetArrivalIsOneHourBeforeEffectiveStart() throws {
        let show = try makeShow()
        let session = DeparturePlanSession(show: show, calendar: calendar)
        let expected = calendar.date(byAdding: .hour, value: -1, to: session.effectiveStartDate)
        XCTAssertEqual(session.defaultTargetArrivalAt, expected)
    }

    func testSaveOptionAndUpsertSavedOrigin() throws {
        let show = try makeShow()
        let container = try ModelContainer(
            for: Show.self, RoundTripPlan.self, SavedOrigin.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(show)

        let session = DeparturePlanSession(show: show, calendar: calendar)
        let plan = session.ensurePlan(existing: nil, in: context)
        let leave = Date(timeIntervalSince1970: 1_800)
        let arrive = Date(timeIntervalSince1970: 3_600)
        let option = DepartureTransportOption(
            id: "opt-1",
            mode: .publicTransit,
            leaveAt: leave,
            arriveAt: arrive,
            durationMinutes: 30,
            distanceMeters: nil,
            summary: "地铁到场",
            experienceTag: "比较稳",
            provider: .appleMaps,
            navigationURL: URL(string: "https://maps.apple.com/?daddr=venue"),
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        try session.save(
            option: option,
            plan: plan,
            origin: "公司",
            destination: "场馆",
            meetingPoint: "东门",
            savedOrigin: nil,
            in: context
        )

        XCTAssertTrue(plan.hasSavedDeparturePlan)
        XCTAssertEqual(plan.departureOrigin, "公司")
        let origins = try context.fetch(FetchDescriptor<SavedOrigin>())
        XCTAssertEqual(origins.count, 1)
        XCTAssertEqual(origins[0].addressText, "公司")
    }

    func testSearchMissingOriginReturnsNeutralFeedback() async throws {
        let show = try makeShow()
        let session = DeparturePlanSession(
            show: show,
            routeProvider: StubDepartureRouteProvider(result: .success([])),
            calendar: calendar
        )
        let outcome = await session.searchOptions(
            origin: "",
            destination: "场馆",
            meetingPoint: "",
            targetArrivalAt: Date(),
            preferredModes: [.publicTransit],
            selectedMode: .publicTransit,
            force: false,
            hasSavedDeparturePlan: false
        )
        XCTAssertEqual(outcome.feedback, .neutral("请先填写或定位出发地"))
        XCTAssertTrue(outcome.recommendations.isEmpty)
    }

    func testAppleMapsDirectionsURL() {
        let url = DeparturePlanSession.appleMapsDirectionsURL(
            origin: "家",
            destination: "场馆"
        )
        XCTAssertEqual(url?.host, "maps.apple.com")
        XCTAssertTrue(url?.absoluteString.contains("saddr=") == true)
        XCTAssertTrue(url?.absoluteString.contains("daddr=") == true)
    }

    private func makeShow() throws -> Show {
        try Show(
            name: "去程 Session 测试",
            date: DateComponents(calendar: calendar, year: 2026, month: 8, day: 10).date!,
            startTime: DateComponents(calendar: calendar, year: 2026, month: 8, day: 10, hour: 20).date!,
            venueAddress: "杭州某处",
            type: .concert
        )
    }
}

private struct StubDepartureRouteProvider: DepartureRouteProviding {
    enum Result {
        case success([DepartureTransportOption])
        case failure(Error)
    }

    let result: Result

    func searchOptions(for request: DepartureRouteRequest) async throws -> [DepartureTransportOption] {
        switch result {
        case .success(let options):
            return options
        case .failure(let error):
            throw error
        }
    }

    @MainActor
    func openNavigation(for option: DepartureTransportOption) {}
}
