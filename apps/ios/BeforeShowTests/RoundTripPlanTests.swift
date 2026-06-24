import SwiftData
import XCTest
@testable import BeforeShow

final class RoundTripPlanTests: XCTestCase {
    @MainActor
    func testOutboundAndReturnCanBeSavedIndependently() throws {
        let show = try Show(name: "落日飞车 北京站", date: Date(), type: .concert)
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
        let show = try Show(name: "草稿测试现场", date: Date(), type: .livehouse)
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
        let show = try Show(name: "证据测试现场", date: Date(), type: .concert)
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
}
