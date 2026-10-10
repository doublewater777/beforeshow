import Foundation
import Observation

@MainActor
@Observable
final class TimetableReviewSession {
    var dayIndex = 0
    private(set) var editingID: UUID?
    private(set) var saveError: TimetableValidationError?
    private(set) var errorPerformanceID: UUID?
    private(set) var errorStageID: UUID?
    private var initialDraft: TimetableDraft?
    private var editingOrder: [UUID: Int] = [:]

    func captureInitialDraft(_ draft: TimetableDraft) {
        if initialDraft == nil { initialDraft = draft }
    }

    func hasChanges(in draft: TimetableDraft) -> Bool {
        initialDraft.map { $0 != draft } ?? false
    }

    func beginEditing(_ id: UUID?, in draft: TimetableDraft) {
        guard let id else { finishEditing(); return }
        guard editingID != id else { return }
        editingID = id
        editingOrder = [:]
        for stage in draft.days.flatMap(\.stages) {
            for (index, performance) in orderedPerformances(in: stage).enumerated() {
                editingOrder[performance.id] = index
            }
        }
    }

    func finishEditing() {
        editingID = nil
        editingOrder = [:]
    }

    func orderedPerformances(in stage: TimetableDraftStage) -> [TimetableDraftPerformance] {
        stage.performances.sorted {
            if editingID != nil, let lhs = editingOrder[$0.id], let rhs = editingOrder[$1.id] {
                return lhs < rhs
            }
            return $0.startsAt == $1.startsAt ? $0.id.uuidString < $1.id.uuidString : $0.startsAt < $1.startsAt
        }
    }

    func prepareSave(_ draft: TimetableDraft) -> Bool {
        clearSaveError()
        do {
            _ = try draft.buildTimetable()
            return true
        } catch let error as TimetableValidationError {
            saveError = error
            reveal(error, in: draft)
            return false
        } catch {
            return false
        }
    }

    func clearSaveError() {
        saveError = nil
        errorPerformanceID = nil
        errorStageID = nil
    }

    private func reveal(_ error: TimetableValidationError, in draft: TimetableDraft) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: draft.timeZoneIdentifier) ?? .current
        for (index, day) in draft.days.enumerated() {
            let performances = day.stages.flatMap(\.performances)
            if error == .emptyDay && day.stages.isEmpty {
                dayIndex = index
                return
            }
            if error == .invalidDayDate, let first = performances.min(by: { $0.startsAt < $1.startsAt }),
               calendar.startOfDay(for: day.date) != day.date || !calendar.isDate(first.startsAt, inSameDayAs: day.date) {
                reveal(first.id, dayIndex: index, draft: draft)
                return
            }
            for stage in day.stages {
                if (error == .emptyStageName && stage.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    || (error == .emptyStage && stage.performances.isEmpty) {
                    dayIndex = index
                    finishEditing()
                    errorStageID = stage.id
                    return
                }
                for performance in stage.performances {
                    if (error == .emptyArtistName && performance.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || (error == .invalidPerformanceInterval && (!performance.startsAt.timeIntervalSince1970.isFinite
                            || !performance.endsAt.timeIntervalSince1970.isFinite || performance.endsAt <= performance.startsAt)) {
                        reveal(performance.id, dayIndex: index, draft: draft)
                        return
                    }
                }
            }
        }
        if error == .overlappingDays {
            let ordered = draft.days.enumerated().sorted { $0.element.date < $1.element.date }
            for (previous, next) in zip(ordered, ordered.dropFirst()) {
                if let last = previous.element.stages.flatMap(\.performances).max(by: { $0.endsAt < $1.endsAt }),
                   let start = next.element.stages.flatMap(\.performances).map(\.startsAt).min(), last.endsAt > start {
                    reveal(last.id, dayIndex: previous.offset, draft: draft)
                    return
                }
            }
        }
    }

    private func reveal(_ id: UUID, dayIndex: Int, draft: TimetableDraft) {
        self.dayIndex = dayIndex
        errorPerformanceID = id
        beginEditing(id, in: draft)
    }
}
