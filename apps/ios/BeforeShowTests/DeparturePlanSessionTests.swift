import XCTest
@testable import BeforeShow

@MainActor
final class DeparturePlanSessionTests: XCTestCase {
    func testReturnMapRouteCanSubmitWithDisplayedDefaultLeaveTime() {
        XCTAssertTrue(
            TravelPlanFormValidation.canSubmitMapRoute(
                origin: place("场馆"),
                destination: place("家"),
                requiresExplicitTime: false,
                hasEnteredTargetTime: false
            )
        )
    }

    func testDefaultTargetArrivalIsOneHourBeforeShowStart() throws {
        let show = try makeShow()
        let session = DeparturePlanSession(show: show, routeProvider: StubTravelRouteProvider())

        XCTAssertEqual(
            session.defaultTargetArrivalAt,
            Calendar.current.date(byAdding: .hour, value: -1, to: session.effectiveStartDate)
        )
    }

    func testRouteTimingUsesArrivalForOutboundAndDepartureForReturn() {
        let targetTime = Date(timeIntervalSince1970: 20_000)

        XCTAssertEqual(RoundTripDirection.outbound.routeTiming(at: targetTime), .arriveAt(targetTime))
        XCTAssertEqual(RoundTripDirection.return.routeTiming(at: targetTime), .departAt(targetTime))
    }

    func testGeneratedPlanCalculatesLeaveTimeFromArrival() async throws {
        let show = try makeShow()
        let route = TravelRouteResult(durationSeconds: 1_800, distanceMeters: 10_000, steps: ["沿主路行驶", "抵达场馆"])
        let session = DeparturePlanSession(show: show, routeProvider: StubTravelRouteProvider(result: .success(route)))
        let arrival = Date(timeIntervalSince1970: 20_000)

        let generated = try await session.generate(
            direction: .outbound,
            mode: .driving,
            origin: place("家"),
            destination: place("场馆"),
            targetTime: arrival
        )

        XCTAssertEqual(generated.arriveAt, arrival)
        XCTAssertEqual(generated.leaveAt, arrival.addingTimeInterval(-1_800))
        XCTAssertEqual(generated.durationMinutes, 30)
    }

    func testDrivingTimelineCollapsesToOriginAndDestination() async throws {
        let show = try makeShow()
        let steps = (1...12).map { "第\($0)段路" }
        let provider = StubTravelRouteProvider(result: .success(.init(durationSeconds: 3_600, distanceMeters: 20_000, steps: steps)))
        let session = DeparturePlanSession(show: show, routeProvider: provider)

        let generated = try await session.generate(
            direction: .outbound,
            mode: .driving,
            origin: place("家"),
            destination: place("场馆"),
            targetTime: Date(timeIntervalSince1970: 20_000)
        )

        XCTAssertEqual(generated.timeline.map(\.kind), [.origin, .destination])
    }

    func testTransitStepsBecomeTransferNodes() async throws {
        let show = try makeShow()
        let provider = StubTravelRouteProvider(
            result: .success(.init(
                durationSeconds: 2_637,
                distanceMeters: 9_371,
                steps: ["步行至火车东站", "乘地铁1号线", "步行至场馆"]
            ))
        )
        let session = DeparturePlanSession(show: show, routeProvider: provider)

        let generated = try await session.generate(
            direction: .outbound,
            mode: .transit,
            origin: place("家"),
            destination: place("场馆"),
            targetTime: Date(timeIntervalSince1970: 20_000)
        )

        XCTAssertEqual(
            generated.timeline.map(\.kind),
            [.origin, .transfer, .transfer, .transfer, .destination]
        )
        XCTAssertEqual(generated.timeline[1].title, "步行至火车东站")
    }

    func testTransitETAWithoutStepsCollapsesToOriginAndDestination() async throws {
        let show = try makeShow()
        let provider = StubTravelRouteProvider(
            result: .success(.init(durationSeconds: 2_637, distanceMeters: 9_371, steps: []))
        )
        let session = DeparturePlanSession(show: show, routeProvider: provider)

        let generated = try await session.generate(
            direction: .return,
            mode: .transit,
            origin: place("场馆"),
            destination: place("家"),
            targetTime: Date(timeIntervalSince1970: 20_000)
        )

        XCTAssertEqual(generated.timeline.map(\.kind), [.origin, .destination])
    }

    func testManualTransitDurationProducesPlanWithoutRouteDistance() throws {
        let show = try makeShow()
        let session = DeparturePlanSession(show: show, routeProvider: StubTravelRouteProvider())
        let leaveAt = Date(timeIntervalSince1970: 20_000)

        let generated = session.generateTransitEstimate(
            direction: .return,
            origin: place("场馆"),
            destination: place("家"),
            targetTime: leaveAt,
            durationMinutes: 50
        )

        XCTAssertEqual(generated.leaveAt, leaveAt)
        XCTAssertEqual(generated.arriveAt, leaveAt.addingTimeInterval(3_000))
        XCTAssertEqual(generated.durationMinutes, 50)
        XCTAssertNil(generated.distanceMeters)
        XCTAssertEqual(generated.timeline.map(\.kind), [.origin, .destination])
    }

    func testDefaultReturnLeaveAtIsAfterShowEndWhenShowInProgress() throws {
        let show = try makeShow()
        let session = DeparturePlanSession(show: show, routeProvider: StubTravelRouteProvider())
        // 开场后 1 小时（concert 默认 4 小时，未散场）
        let now = session.effectiveStartDate.addingTimeInterval(3_600)

        XCTAssertEqual(
            session.defaultReturnLeaveAt(now: now),
            Calendar.current.date(
                byAdding: .minute,
                value: 15,
                to: session.effectiveStartDate.addingTimeInterval(4 * 3_600)
            )
        )
    }

    func testDefaultReturnLeaveAtIsFifteenMinutesFromNowAfterShowEnd() throws {
        let show = try makeShow()
        let session = DeparturePlanSession(show: show, routeProvider: StubTravelRouteProvider())
        // 散场后（concert 默认 4 小时 + 1 小时）
        let now = session.effectiveStartDate.addingTimeInterval(5 * 3_600)

        XCTAssertEqual(
            session.defaultReturnLeaveAt(now: now),
            Calendar.current.date(byAdding: .minute, value: 15, to: now)
        )
    }

    func testPostponementStatusAndDateArePartOfShowFingerprint() throws {
        let show = try makeShow()
        let originalFingerprint = DeparturePlanSession(
            show: show,
            routeProvider: StubTravelRouteProvider()
        ).showFingerprint

        show.markPostponed(newDate: nil)
        let unknownDateFingerprint = DeparturePlanSession(
            show: show,
            routeProvider: StubTravelRouteProvider()
        ).showFingerprint

        show.markPostponed(newDate: Date(timeIntervalSince1970: 28_000))
        let datedFingerprint = DeparturePlanSession(
            show: show,
            routeProvider: StubTravelRouteProvider()
        ).showFingerprint

        XCTAssertNotEqual(originalFingerprint, unknownDateFingerprint)
        XCTAssertNotEqual(unknownDateFingerprint, datedFingerprint)
    }

    private func makeShow() throws -> Show {
        try Show(
            name: "路线测试",
            date: Date(timeIntervalSince1970: 18_000),
            startTime: Date(timeIntervalSince1970: 18_000),
            city: "杭州",
            venueName: "场馆",
            venueAddress: "场馆地址",
            type: .concert
        )
    }

    private func place(_ name: String) -> TravelPlace {
        TravelPlace(name: name, address: "\(name)地址", latitude: 30, longitude: 120)
    }
}

private struct StubTravelRouteProvider: TravelRouteProviding {
    var result: Result<TravelRouteResult, Error> = .success(
        TravelRouteResult(durationSeconds: 1_200, distanceMeters: 4_000, steps: ["前往终点"])
    )

    func route(
        from origin: TravelPlace,
        to destination: TravelPlace,
        mode: TravelMode,
        timing: TravelRouteTiming
    ) async throws -> TravelRouteResult {
        try result.get()
    }
}
