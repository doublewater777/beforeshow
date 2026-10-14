import Foundation
import Observation
import SwiftData

/// An imported timetable under review. It lives in its own in-memory store so
/// the stage matrix, inspector and add form can edit it with their usual code,
/// while the saved timetable stays untouched until 确认保存.
@MainActor
@Observable
final class TimetableImportSession: Identifiable {
    let id = UUID()
    let container: ModelContainer
    let timetable: Timetable
    /// Originals picked for this import; empty when the source was text.
    let imagesData: [Data]
    let carriedOverInterestedCount: Int
    var selectedDayID: UUID

    init(result: TimetableImportResult, imagesData: [Data], carriedOverInterestedCount: Int = 0) throws {
        let configuration = ModelConfiguration("TimetableImportReview", isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(
            for: Timetable.self, TimetableDay.self, TimetableStage.self, TimetablePerformance.self,
            configurations: configuration
        )
        let timetable = try result.draft.buildTimetable()
        container.mainContext.insert(timetable)
        try container.mainContext.save()
        self.timetable = timetable
        self.imagesData = imagesData
        self.carriedOverInterestedCount = carriedOverInterestedCount
        self.selectedDayID = timetable.orderedDays.first?.id ?? UUID()
    }

    var context: ModelContext { container.mainContext }

    /// The reviewed timetable as a draft, without columns or days left empty.
    func reviewedDraft() -> TimetableDraft {
        var draft = TimetableDraft(from: timetable)
        for index in draft.days.indices {
            draft.days[index].stages.removeAll { $0.performances.isEmpty }
            for (order, stageIndex) in draft.days[index].stages.indices.enumerated() {
                draft.days[index].stages[stageIndex].sortOrder = order
            }
        }
        draft.days.removeAll { $0.stages.isEmpty }
        return draft
    }
}
