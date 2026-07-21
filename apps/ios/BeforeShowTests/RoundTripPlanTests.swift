import MapKit
import XCTest
@testable import BeforeShow

final class RoundTripPlanTests: XCTestCase {
    func testOutboundAndReturnAreSavedIndependently() {
        let plan = RoundTripPlan(showID: UUID())

        plan.save(makeTravelPlan(direction: .outbound, summary: "去场馆"))

        XCTAssertEqual(plan.outboundPlan?.summary, "去场馆")
        XCTAssertNil(plan.returnPlan)

        plan.save(makeTravelPlan(direction: .return, summary: "回家"))

        XCTAssertEqual(plan.outboundPlan?.summary, "去场馆")
        XCTAssertEqual(plan.returnPlan?.summary, "回家")
    }

    func testSavingSameDirectionReplacesOnlyThatDirection() {
        let plan = RoundTripPlan(showID: UUID())
        plan.save(makeTravelPlan(direction: .outbound, summary: "旧去程"))
        plan.save(makeTravelPlan(direction: .return, summary: "返程"))

        plan.save(makeTravelPlan(direction: .outbound, summary: "新去程"))

        XCTAssertEqual(plan.outboundPlan?.summary, "新去程")
        XCTAssertEqual(plan.returnPlan?.summary, "返程")
    }

    func testShowFingerprintChangeInvalidatesBothDirectionsWithoutDeletingThem() {
        let plan = RoundTripPlan(showID: UUID())
        plan.save(makeTravelPlan(direction: .outbound, fingerprint: "before"))
        plan.save(makeTravelPlan(direction: .return, fingerprint: "before"))

        plan.invalidatePlans(ifShowFingerprintChangedTo: "after")

        XCTAssertEqual(plan.outboundPlan?.validity, .needsRegeneration)
        XCTAssertEqual(plan.returnPlan?.validity, .needsRegeneration)
        XCTAssertTrue(plan.hasPlan(for: .outbound))
        XCTAssertFalse(plan.hasValidPlan(for: .outbound))
    }

    func testFiveTravelModesHaveFixedOrderAndCustomIsNotMapKit() {
        XCTAssertEqual(TravelMode.allCases, [.driving, .walking, .transit, .cycling, .custom])
        XCTAssertEqual(TravelMode.driving.mapKitTransportType, .automobile)
        XCTAssertEqual(TravelMode.walking.mapKitTransportType, .walking)
        XCTAssertEqual(TravelMode.transit.mapKitTransportType, .transit)
        XCTAssertEqual(TravelMode.cycling.mapKitTransportType, .cycling)
        XCTAssertNil(TravelMode.custom.mapKitTransportType)
    }

    func testTransitUsesETACalculationWhileOtherMapModesUseRoutes() {
        XCTAssertEqual(TravelMode.transit.mapKitCalculation, .estimatedTime)
        XCTAssertEqual(TravelMode.driving.mapKitCalculation, .route)
        XCTAssertEqual(TravelMode.walking.mapKitCalculation, .route)
        XCTAssertEqual(TravelMode.cycling.mapKitCalculation, .route)
        XCTAssertNil(TravelMode.custom.mapKitCalculation)
    }

    func testHomeRouteStateUsesOutboundBeforeShowAndReturnAfterStart() {
        let plan = RoundTripPlan(showID: UUID())
        plan.save(makeTravelPlan(direction: .outbound))

        XCTAssertTrue(HomeFeatureCopySource.hasRoutePlan(plan, for: .pre))
        XCTAssertFalse(HomeFeatureCopySource.hasRoutePlan(plan, for: .live))
        XCTAssertFalse(HomeFeatureCopySource.hasRoutePlan(plan, for: .ended))

        plan.save(makeTravelPlan(direction: .return))

        XCTAssertTrue(HomeFeatureCopySource.hasRoutePlan(plan, for: .live))
        XCTAssertTrue(HomeFeatureCopySource.hasRoutePlan(plan, for: .ended))
    }

    func testEndedPhasePromotesReturnCardAndUsesReturnEmptyCopy() {
        XCTAssertEqual(HomeFeatureCopySource.order(for: .ended).first, .route)
        XCTAssertTrue(HomeFeatureCopySource.recommended(for: .ended).contains(.route))
        let copy = HomeFeatureCopySource.copy(for: .route, phase: .ended)
        XCTAssertEqual(copy.note, "填好目的地和离开时间")
        XCTAssertEqual(copy.cta, "备好返程")
    }

    func testInvalidPlanDoesNotFullyRestorePlacesAndTimes() {
        var invalid = makeTravelPlan(direction: .outbound, fingerprint: "current")
        invalid.validity = .needsRegeneration
        let valid = makeTravelPlan(direction: .outbound, fingerprint: "current")

        XCTAssertFalse(TravelPlanFormValidation.shouldRestorePlacesAndTimes(from: invalid, fingerprint: "current"))
        XCTAssertTrue(TravelPlanFormValidation.shouldRestorePlacesAndTimes(from: valid, fingerprint: "current"))
    }

    func testInvalidOutboundIsNotReusedAsReturnSeed() {
        var invalidOutbound = makeTravelPlan(direction: .outbound, fingerprint: "current")
        invalidOutbound.validity = .needsRegeneration
        let validOutbound = makeTravelPlan(direction: .outbound, fingerprint: "current")

        XCTAssertNil(TravelPlanFormValidation.returnSeed(fromOutbound: invalidOutbound, fingerprint: "current"))
        XCTAssertNil(TravelPlanFormValidation.returnSeed(fromOutbound: nil, fingerprint: "current"))

        let seed = TravelPlanFormValidation.returnSeed(fromOutbound: validOutbound, fingerprint: "current")
        XCTAssertEqual(seed?.mode, validOutbound.mode)
        XCTAssertEqual(seed?.origin, validOutbound.destination)
        XCTAssertEqual(seed?.destination, validOutbound.origin)
    }

    /// 指纹已变但首页失效任务尚未跑（validity 仍为 .valid）时，不得回填/作返程种子。
    func testOldFingerprintIsRejectedBeforeHomeInvalidationRuns() {
        let stale = makeTravelPlan(direction: .outbound, fingerprint: "venue-A")
        XCTAssertEqual(stale.validity, .valid)

        let currentFingerprint = "venue-B"
        XCTAssertFalse(TravelPlanFormValidation.isCurrent(stale, fingerprint: currentFingerprint))
        XCTAssertFalse(
            TravelPlanFormValidation.shouldRestorePlacesAndTimes(from: stale, fingerprint: currentFingerprint)
        )
        XCTAssertNil(
            TravelPlanFormValidation.returnSeed(fromOutbound: stale, fingerprint: currentFingerprint)
        )

        // 同指纹仍可回填
        XCTAssertTrue(TravelPlanFormValidation.isCurrent(stale, fingerprint: "venue-A"))
        XCTAssertNotNil(
            TravelPlanFormValidation.returnSeed(fromOutbound: stale, fingerprint: "venue-A")
        )
    }

    func testInvalidatePlansMarksStaleFingerprintEvenWhenStillValid() {
        let store = RoundTripPlan(showID: UUID())
        store.save(makeTravelPlan(direction: .outbound, fingerprint: "venue-A"))
        store.save(makeTravelPlan(direction: .return, fingerprint: "venue-A"))
        XCTAssertEqual(store.outboundPlan?.validity, .valid)

        let didInvalidate = store.invalidatePlans(ifShowFingerprintChangedTo: "venue-B")
        XCTAssertTrue(didInvalidate)
        XCTAssertEqual(store.outboundPlan?.validity, .needsRegeneration)
        XCTAssertEqual(store.returnPlan?.validity, .needsRegeneration)
        // 失效后也不得回填
        XCTAssertFalse(
            TravelPlanFormValidation.shouldRestorePlacesAndTimes(
                from: store.outboundPlan!,
                fingerprint: "venue-B"
            )
        )
    }

    func testFormDirectionIsResolvedOnceFromNowNotLiveClock() throws {
        let show = try Show(
            name: "方向测试",
            date: Date(timeIntervalSince1970: 18_000),
            startTime: Date(timeIntervalSince1970: 18_000),
            type: .concert
        )
        let beforeStart = Date(timeIntervalSince1970: 17_000)
        let afterStart = Date(timeIntervalSince1970: 19_000)

        // 父视图应在打开时保存这一次解析结果，而不是让 View 随实时时钟重算。
        let openedDirection = RoundTripPlanDirectionResolver.resolve(show: show, now: beforeStart)
        XCTAssertEqual(openedDirection, .outbound)
        XCTAssertEqual(RoundTripPlanDirectionResolver.resolve(show: show, now: afterStart), .return)
        // 已打开表单持有的方向不随后续时间变化。
        XCTAssertEqual(openedDirection, .outbound)
    }

    func testMapKitArriveAtRefinesDepartureFromFirstPassDuration() {
        let arrive = Date(timeIntervalSince1970: 30_000)
        let threeHours: TimeInterval = 3 * 3_600

        XCTAssertEqual(
            MapKitTravelRouteProvider.provisionalDeparture(forArrival: arrive),
            arrive.addingTimeInterval(-MapKitTravelRouteProvider.provisionalLeadTime)
        )
        XCTAssertEqual(
            MapKitTravelRouteProvider.refinedDeparture(forArrival: arrive, duration: threeHours),
            arrive.addingTimeInterval(-threeHours)
        )

        let transitArriveRequest = MKDirections.Request()
        MapKitTravelRouteProvider.applyTiming(.arriveAt(arrive), calculation: .estimatedTime, to: transitArriveRequest)
        XCTAssertEqual(transitArriveRequest.arrivalDate, arrive)

        let depart = Date(timeIntervalSince1970: 20_000)
        let departRequest = MKDirections.Request()
        MapKitTravelRouteProvider.applyTiming(.departAt(depart), calculation: .route, to: departRequest)
        XCTAssertEqual(departRequest.departureDate, depart)
    }

    private func makeTravelPlan(
        direction: RoundTripDirection,
        summary: String = "路线",
        fingerprint: String = "show-v1"
    ) -> TravelPlan {
        TravelPlan(
            direction: direction,
            mode: .driving,
            origin: TravelPlace(name: "起点", address: "起点地址", latitude: 30, longitude: 120),
            destination: TravelPlace(name: "终点", address: "终点地址", latitude: 31, longitude: 121),
            leaveAt: Date(timeIntervalSince1970: 1_000),
            arriveAt: Date(timeIntervalSince1970: 2_000),
            durationMinutes: 17,
            distanceMeters: 5_000,
            summary: summary,
            timeline: [
                TravelTimelineNode(kind: .origin, title: "从起点出发", date: Date(timeIntervalSince1970: 1_000)),
                TravelTimelineNode(kind: .destination, title: "抵达终点", date: Date(timeIntervalSince1970: 2_000)),
            ],
            showFingerprint: fingerprint,
            capturedAt: Date(timeIntervalSince1970: 900)
        )
    }
}
