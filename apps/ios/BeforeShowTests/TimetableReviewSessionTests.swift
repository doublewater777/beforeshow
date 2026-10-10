import XCTest
@testable import BeforeShow

@MainActor
final class TimetableReviewSessionTests: XCTestCase {
    func testSavingFromAnotherDayRevealsTheInvalidPerformanceWithoutMutatingDraft() {
        for error in [TimetableValidationError.invalidPerformanceInterval, .emptyArtistName, .emptyStageName, .overlappingDays] {
            var draft = fixture()
            let invalidID = draft.days[0].stages[0].performances[0].id
            if error == .invalidPerformanceInterval {
                draft.days[0].stages[0].performances[0].endsAt = draft.days[0].stages[0].performances[0].startsAt
            } else if error == .emptyArtistName {
                draft.days[0].stages[0].performances[0].artistName = "  "
            } else if error == .emptyStageName {
                draft.days[0].stages[0].name = "  "
            } else {
                draft.days[0].stages[0].performances[0].endsAt = draft.days[1].date.addingTimeInterval(19 * 3600)
            }
            let original = draft
            let session = TimetableReviewSession()
            session.dayIndex = 1
            XCTAssertFalse(session.prepareSave(draft))
            XCTAssertEqual(session.saveError, error)
            XCTAssertEqual(session.dayIndex, 0)
            if error == .emptyStageName {
                XCTAssertNil(session.editingID)
                XCTAssertEqual(session.errorStageID, draft.days[0].stages[0].id)
            } else {
                XCTAssertEqual(session.editingID, invalidID)
                XCTAssertEqual(session.errorPerformanceID, invalidID)
            }
            XCTAssertEqual(draft, original)
            draft.days[0].stages[0].performances[0].artistName = "First"
            draft.days[0].stages[0].name = "Main"
            draft.days[0].stages[0].performances[0].endsAt = draft.days[0].stages[0].performances[0].startsAt.addingTimeInterval(3600)
            XCTAssertTrue(session.prepareSave(draft))
            XCTAssertNil(session.saveError)
        }
    }

    func testSameStageOverlapRemainsAWarningAndDoesNotBlockSaving() {
        var draft = fixture()
        draft.days[0].stages[0].performances[1].startsAt = draft.days[0].date.addingTimeInterval(18.5 * 3600)
        XCTAssertTrue(TimetableReviewSession().prepareSave(draft))
    }

    func testEditingKeepsRowPositionUntilFinishedThenUsesUpdatedTime() {
        var draft = fixture()
        let session = TimetableReviewSession()
        let initial = draft.days[0].stages[0].performances.map(\.id)
        session.beginEditing(initial[0], in: draft)
        draft.days[0].stages[0].performances[0].startsAt = draft.days[0].date.addingTimeInterval(22 * 3600)
        draft.days[0].stages[0].performances[0].endsAt = draft.days[0].date.addingTimeInterval(23 * 3600)
        XCTAssertEqual(session.orderedPerformances(in: draft.days[0].stages[0]).map(\.id), initial)
        draft.days[0].stages[0].performances[0].endsAt = draft.days[0].date.addingTimeInterval(21 * 3600)
        XCTAssertFalse(session.prepareSave(draft))
        XCTAssertEqual(session.orderedPerformances(in: draft.days[0].stages[0]).map(\.id), initial)
        session.finishEditing()
        XCTAssertEqual(session.orderedPerformances(in: draft.days[0].stages[0]).map(\.id), initial.reversed())
    }

    func testUnsavedChangesIncludeArtistBindingAndClearWhenReverted() {
        var draft = fixture()
        let original = draft
        let session = TimetableReviewSession()
        session.captureInitialDraft(draft)
        XCTAssertFalse(session.hasChanges(in: draft))
        draft.days[0].stages[0].performances[0].connectArtist(
            RecognizedArtist(id: "123", canonicalName: "First", avatarURL: nil, appleMusicURL: nil)
        )
        session.captureInitialDraft(draft)
        XCTAssertTrue(session.hasChanges(in: draft))
        draft = original
        XCTAssertFalse(session.hasChanges(in: draft))
    }

    private func fixture() -> TimetableDraft {
        let day = Date(timeIntervalSince1970: 1790956800)
        return TimetableDraft(timeZoneIdentifier: "Asia/Taipei", days: (0..<2).map { index in
            let date = day.addingTimeInterval(Double(index) * 86400)
            return TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [
                    TimetableDraftPerformance(artistName: "First", startsAt: date.addingTimeInterval(18 * 3600), endsAt: date.addingTimeInterval(19 * 3600)),
                    TimetableDraftPerformance(artistName: "Second", startsAt: date.addingTimeInterval(20 * 3600), endsAt: date.addingTimeInterval(21 * 3600))
                ])
            ])
        })
    }
}
