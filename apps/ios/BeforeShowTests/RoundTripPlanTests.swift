import CoreLocation
import MapKit
import SwiftData
import XCTest
@testable import BeforeShow

final class RoundTripPlanTests: XCTestCase {
    @MainActor
    func testSavedDeparturePlanStoresOneStructuredOption() throws {
        let show = try Show(name: "康士坦杭州站", date: Date(), startTime: Date(), type: .livehouse)
        let plan = RoundTripPlan(showID: show.id)
        let leaveAt = Date(timeIntervalSince1970: 1_800)
        let arriveAt = Date(timeIntervalSince1970: 3_600)
        let option = DepartureTransportOption(
            id: "public-1",
            mode: .publicTransit,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: 30,
            distanceMeters: nil,
            summary: "地铁到场，少换乘。",
            experienceTag: "比较稳",
            provider: .appleMaps,
            navigationURL: URL(string: "https://maps.apple.com/?daddr=30.25,120.17"),
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        plan.saveDeparture(option: option, origin: "公司", destination: "杭州 MAO Livehouse", meetingPoint: "入口")

        XCTAssertTrue(plan.hasSavedDeparturePlan)
        XCTAssertEqual(plan.departureOrigin, "公司")
        XCTAssertEqual(plan.departureDestination, "杭州 MAO Livehouse")
        XCTAssertEqual(plan.departureMeetingPoint, "入口")
        XCTAssertEqual(plan.savedDepartureMode, .publicTransit)
        XCTAssertEqual(plan.savedDepartureProvider, .appleMaps)
        XCTAssertEqual(plan.departureLeaveAt, leaveAt)
        XCTAssertEqual(plan.departureArriveAt, arriveAt)
        XCTAssertEqual(plan.departureDurationMinutes, 30)
        XCTAssertEqual(plan.departureSummary, "地铁到场，少换乘。")
        XCTAssertEqual(plan.outboundContent, "地铁到场，少换乘。")
        XCTAssertTrue(plan.hasOutboundPlan)
    }

    func testHasOutboundPlanIsSinglePredicateForTipsAndStatus() {
        let empty = RoundTripPlan(showID: UUID())
        XCTAssertFalse(empty.hasSavedDeparturePlan)
        XCTAssertFalse(empty.hasOutboundPlan)

        let legacyTextOnly = RoundTripPlan(showID: UUID(), outboundContent: "  地铁到场  ")
        XCTAssertFalse(legacyTextOnly.hasSavedDeparturePlan)
        XCTAssertTrue(legacyTextOnly.hasOutboundPlan)

        let whitespaceOnly = RoundTripPlan(showID: UUID(), outboundContent: "   ")
        XCTAssertFalse(whitespaceOnly.hasOutboundPlan)

        let structured = RoundTripPlan(showID: UUID())
        let option = DepartureTransportOption(
            id: "opt",
            mode: .driving,
            leaveAt: Date(timeIntervalSince1970: 1_000),
            arriveAt: Date(timeIntervalSince1970: 2_000),
            durationMinutes: 20,
            distanceMeters: nil,
            summary: "开车",
            experienceTag: "比较快",
            provider: .appleMaps,
            navigationURL: nil,
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        structured.saveDeparture(option: option, origin: "家", destination: "场馆", meetingPoint: nil)
        XCTAssertTrue(structured.hasSavedDeparturePlan)
        XCTAssertTrue(structured.hasOutboundPlan)
    }

    func testSavingNewDeparturePlanReplacesThePreviousOne() {
        let plan = RoundTripPlan(showID: UUID())
        let first = DepartureTransportOption(
            id: "public-1",
            mode: .publicTransit,
            leaveAt: Date(timeIntervalSince1970: 1_000),
            arriveAt: Date(timeIntervalSince1970: 2_000),
            durationMinutes: 20,
            distanceMeters: nil,
            summary: "公共交通。",
            experienceTag: "比较稳",
            provider: .appleMaps,
            navigationURL: nil,
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let second = DepartureTransportOption(
            id: "taxi-1",
            mode: .taxiReference,
            leaveAt: Date(timeIntervalSince1970: 1_400),
            arriveAt: Date(timeIntervalSince1970: 2_000),
            durationMinutes: 10,
            distanceMeters: 5_000,
            summary: "打车参考。",
            experienceTag: "适合赶时间",
            provider: .appleMaps,
            navigationURL: nil,
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        plan.saveDeparture(option: first, origin: "家", destination: "场馆", meetingPoint: nil)
        plan.saveDeparture(option: second, origin: "公司", destination: "场馆", meetingPoint: nil)

        XCTAssertEqual(plan.savedDepartureMode, .taxiReference)
        XCTAssertEqual(plan.departureOrigin, "公司")
        XCTAssertEqual(plan.departureDurationMinutes, 10)
        XCTAssertEqual(plan.departureSummary, "打车参考。")
    }

    func testAppleMapsDirectionsURLUsesTransitModeFlag() {
        let origin = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 30.279, longitude: 120.166))
        )
        let destination = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 30.250, longitude: 120.210))
        )

        let url = MapKitDepartureRouteProvider.appleMapsDirectionsURL(
            origin: origin,
            destination: destination,
            mode: .publicTransit
        )

        XCTAssertEqual(url?.host, "maps.apple.com")
        XCTAssertTrue(url?.absoluteString.contains("dirflg=r") == true)
        XCTAssertTrue(url?.absoluteString.contains("saddr=30.279,120.166") == true)
        XCTAssertTrue(url?.absoluteString.contains("daddr=30.25,120.21") == true || url?.absoluteString.contains("daddr=30.25,120.210") == true)
    }

    @MainActor
    func testEstimatedDepartureRouteProviderUsesAppleMapsProviderID() async throws {
        let show = try Show(
            name: "路线测试现场",
            date: Date(timeIntervalSince1970: 3_600 * 20),
            startTime: Date(timeIntervalSince1970: 3_600 * 20),
            city: "杭州",
            venueName: "MAO Livehouse",
            type: .livehouse
        )
        let request = DepartureRouteRequest(
            show: show,
            origin: "西湖文化广场",
            destination: "杭州 MAO Livehouse",
            meetingPoint: nil,
            targetArrivalAt: Date(timeIntervalSince1970: 3_600 * 19),
            preferredModes: [.publicTransit, .taxiReference, .driving],
            notes: nil
        )

        let options = try await EstimatedDepartureRouteProvider().searchOptions(for: request)

        XCTAssertEqual(options.map(\.mode), [.publicTransit, .taxiReference, .driving])
        XCTAssertEqual(options.map(\.provider), [.appleMaps, .appleMaps, .appleMaps])
        XCTAssertTrue(options.allSatisfy { $0.arriveAt == request.targetArrivalAt })
    }

    @MainActor
    func testOutboundAndReturnCanBeSavedIndependently() throws {
        let show = try Show(name: "落日飞车 北京站", date: Date(), startTime: Date(), type: .concert)
        let plan = RoundTripPlan(showID: show.id)

        let container = try ModelContainer(
            for: Show.self, RoundTripPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(show)
        container.mainContext.insert(plan)

        plan.saveOutbound("从酒店出发，提前到场。")
        try container.mainContext.save()

        let plans = try container.mainContext.fetch(FetchDescriptor<RoundTripPlan>())
        XCTAssertEqual(plans[0].outboundContent, "从酒店出发，提前到场。")
        XCTAssertNil(plans[0].returnContent)
        XCTAssertEqual(plans[0].returnState, .undecided)
    }

    func testUndecidedReturnIsANormalStateWithoutCompletion() {
        let plan = RoundTripPlan(showID: UUID())

        plan.markReturnUndecided(note: "散场后再看地铁和打车情况。")

        XCTAssertEqual(plan.returnState, .undecided)
        XCTAssertEqual(plan.returnNote, "散场后再看地铁和打车情况。")
        XCTAssertEqual(ReturnPlanState.allCases, [.undecided, .planned])
    }

    func testGeneratedDraftDoesNotOverwriteSavedPlan() throws {
        let show = try Show(name: "草稿测试现场", date: Date(), startTime: Date(), type: .livehouse)
        let plan = RoundTripPlan(showID: show.id)
        plan.saveReturn("用户自己保存的返程。")

        _ = try RoundTripDraftBuilder().makeDraft(
            for: RoundTripDraftRequest(
                show: show,
                direction: .return,
                origin: nil,
                destination: "家",
                hotel: nil,
                meetingPoint: nil,
                notes: nil
            ),
            evidence: [RoundTripEvidence(title: "地铁运营公告")],
            proposedSummary: "模型生成的新返程草稿。",
            proposedSteps: [RoundTripDraftStep(title: "散场后", detail: "先确认出口。")]
        )

        XCTAssertEqual(plan.returnContent, "用户自己保存的返程。")
    }

    func testDraftRequiresDirectionInformationAndEvidence() throws {
        let show = try Show(name: "证据测试现场", date: Date(), startTime: Date(), type: .concert)
        let builder = RoundTripDraftBuilder()

        XCTAssertThrowsError(
            try builder.makeDraft(
                for: RoundTripDraftRequest(
                    show: show,
                    direction: .outbound,
                    origin: nil,
                    destination: nil,
                    hotel: nil,
                    meetingPoint: nil,
                    notes: nil
                ),
                evidence: [RoundTripEvidence(title: "场馆交通公告")],
                proposedSummary: "提前出发。",
                proposedSteps: [RoundTripDraftStep(title: "出发", detail: "去场馆。")]
            )
        ) { error in
            XCTAssertEqual(error as? RoundTripDraftError, .insufficientDirectionInformation)
        }

        XCTAssertThrowsError(
            try builder.makeDraft(
                for: RoundTripDraftRequest(
                    show: show,
                    direction: .outbound,
                    origin: "人民广场",
                    destination: nil,
                    hotel: nil,
                    meetingPoint: nil,
                    notes: nil
                ),
                evidence: [],
                proposedSummary: "提前出发。",
                proposedSteps: [RoundTripDraftStep(title: "出发", detail: "去场馆。")]
            )
        ) { error in
            XCTAssertEqual(error as? RoundTripDraftError, .missingReliableEvidence)
        }
    }

    func testGenerationResponseDecodesEditableDraft() throws {
        let payload = """
        {
          "type": "roundTripDraft",
          "direction": "outbound",
          "summary": "提前 90 分钟出发。",
          "steps": [
            { "title": "出发", "detail": "从酒店去场馆。" }
          ],
          "evidence": [
            { "title": "场馆交通公告", "url": "https://example.com/traffic" }
          ]
        }
        """

        let draft = try JSONDecoder().decode(RoundTripDraft.self, from: Data(payload.utf8))

        XCTAssertEqual(draft.direction, .outbound)
        XCTAssertTrue(draft.editableText.contains("提前 90 分钟出发。"))
        XCTAssertTrue(draft.editableText.contains("依据：场馆交通公告"))
    }

    func testGenerationResponseRejectsUnsupportedFields() {
        let payload = """
        {
          "type": "roundTripDraft",
          "direction": "outbound",
          "summary": "提前出发。",
          "steps": [{ "title": "出发", "detail": "去场馆。" }],
          "evidence": [{ "title": "公告" }],
          "videoUrl": "https://example.com/video.mp4"
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(RoundTripDraft.self, from: Data(payload.utf8))
        )
    }

    // MARK: - 常用出发地
    @MainActor
    func testSavedOriginTrimsTextAndPersists() throws {
        let container = try ModelContainer(
            for: SavedOrigin.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let origin = SavedOrigin(name: "  家  ", addressText: "  杭州市西湖区  ")
        context.insert(origin)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SavedOrigin>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "家")
        XCTAssertEqual(fetched[0].addressText, "杭州市西湖区")
        XCTAssertNil(fetched[0].latitude)
    }

    func testSavedOriginRetainsCoordinates() {
        let origin = SavedOrigin(name: "公司", addressText: "公司", latitude: 30.27, longitude: 120.16)
        XCTAssertEqual(origin.latitude, 30.27)
        XCTAssertEqual(origin.longitude, 120.16)
    }

    // MARK: - 出行计划详情页：地图跳转兜底
    func testAppleMapsDirectionsURLWithOriginAndDestination() {
        let url = DeparturePlanSession.appleMapsDirectionsURL(origin: "西湖文化广场", destination: "杭州 MAO Livehouse")
        XCTAssertEqual(url?.host, "maps.apple.com")
        let absolute = url?.absoluteString ?? ""
        XCTAssertTrue(absolute.contains("saddr="))
        XCTAssertTrue(absolute.contains("daddr="))
    }

    func testAppleMapsDirectionsURLOmitsOriginWhenEmpty() {
        let url = DeparturePlanSession.appleMapsDirectionsURL(origin: nil, destination: "场馆")
        let absolute = url?.absoluteString ?? ""
        XCTAssertFalse(absolute.contains("saddr="))
        XCTAssertTrue(absolute.contains("daddr="))
    }

    func testAppleMapsDirectionsURLReturnsNilWithoutDestination() {
        XCTAssertNil(DeparturePlanSession.appleMapsDirectionsURL(origin: "家", destination: nil))
        XCTAssertNil(DeparturePlanSession.appleMapsDirectionsURL(origin: "家", destination: "   "))
    }

}
