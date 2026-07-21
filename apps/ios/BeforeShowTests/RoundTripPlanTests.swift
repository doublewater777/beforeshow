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
        var invalid = makeTravelPlan(direction: .outbound)
        invalid.validity = .needsRegeneration
        let valid = makeTravelPlan(direction: .outbound)

        XCTAssertFalse(TravelPlanFormValidation.shouldRestorePlacesAndTimes(from: invalid))
        XCTAssertTrue(TravelPlanFormValidation.shouldRestorePlacesAndTimes(from: valid))
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

        XCTAssertEqual(RoundTripPlanDirectionResolver.resolve(show: show, now: beforeStart), .outbound)
        XCTAssertEqual(RoundTripPlanDirectionResolver.resolve(show: show, now: afterStart), .return)
    }

    func testMapKitAppliesDepartAtToAllModesAndSeedsRouteArriveAt() {
        let depart = Date(timeIntervalSince1970: 20_000)
        let arrive = Date(timeIntervalSince1970: 30_000)

        let departRequest = MKDirections.Request()
        MapKitTravelRouteProvider.applyTiming(.departAt(depart), calculation: .route, to: departRequest)
        XCTAssertEqual(departRequest.departureDate, depart)

        let transitArriveRequest = MKDirections.Request()
        MapKitTravelRouteProvider.applyTiming(.arriveAt(arrive), calculation: .estimatedTime, to: transitArriveRequest)
        XCTAssertEqual(transitArriveRequest.arrivalDate, arrive)

        let drivingArriveRequest = MKDirections.Request()
        MapKitTravelRouteProvider.applyTiming(.arriveAt(arrive), calculation: .route, to: drivingArriveRequest)
        XCTAssertEqual(drivingArriveRequest.departureDate, arrive.addingTimeInterval(-3_600))
        XCTAssertNil(drivingArriveRequest.arrivalDate)
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
