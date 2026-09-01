import Foundation
import SwiftData

// MARK: - Add Show Lifecycle & Persistence

enum AddShowLifecycleResolution: Equatable {
    case future
    case needsEndConfirmation
    case ended
}

enum AddShowLifecyclePolicy {
    static func minimumEndTime(for show: Show, calendar: Calendar = .current) -> Date {
        CurrentShowTimeState.minimumConfirmableEnd(for: show, calendar: calendar)
    }

    static func canConfirmEnd(
        for show: Show,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        minimumEndTime(for: show, calendar: calendar) <= now
    }

    static func resolution(
        for show: Show,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AddShowLifecycleResolution {
        if show.endedAt != nil {
            return .ended
        }

        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        switch state.kind {
        case .before:
            return .future
        case .today:
            guard let start = state.effectiveStartTime, now >= start else {
                return .future
            }
            return .needsEndConfirmation
        case .dayEnded, .postShow:
            return .needsEndConfirmation
        case .ended:
            return .ended
        case .canceled, .postponed:
            return .future
        }
    }
}

enum AddShowFinalLifecycle: Equatable {
    case future
    case live
    case ended
}

enum AddShowSaveOutcome: String, Equatable {
    case future
    case current
    case footprint
}

enum AddShowSuccessCopy {
    static func title(isDuplicate: Bool) -> String {
        BSLocalization.text(isDuplicate ? "这场已经在 BeforeShow 里了" : "已添加现场")
    }

    static func status(for outcome: AddShowSaveOutcome) -> String {
        switch outcome {
        case .future:
            return BSLocalization.text("已加入我的现场")
        case .current:
            return BSLocalization.text("已设为当前现场")
        case .footprint:
            return BSLocalization.text("已收进足迹")
        }
    }
}

struct AddShowPersistenceResult {
    let outcome: AddShowSaveOutcome
    let notificationState: NotificationSchedulingState?
}

enum AddShowPersistenceError: Error, Equatable {
    case duplicateShow(existingShowID: UUID)
}

@MainActor
enum AddShowPersistenceCoordinator {
    static func persist(
        _ show: Show,
        lifecycle: AddShowFinalLifecycle,
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> AddShowPersistenceResult {
        let persistedShows = try modelContext.fetch(FetchDescriptor<Show>())
        if let duplicate = ShowDuplicateMatcher.firstDuplicate(of: show, in: persistedShows) {
            throw AddShowPersistenceError.duplicateShow(existingShowID: duplicate.id)
        }

        let existingCurrent = CurrentShowSession().selectCurrentShow(
            from: persistedShows,
            manualSelection: selections.first,
            now: now
        )

        modelContext.insert(show)

        switch lifecycle {
        case .ended:
            if show.endedAt == nil {
                show.markAddedAsHistorical()
            }
            let notificationState: NotificationSchedulingState?
            if show.endedAt != nil {
                let state = notificationStates.first
                    ?? NotificationSchedulingState(focusedShowID: existingCurrent?.id)
                if notificationStates.isEmpty {
                    modelContext.insert(state)
                } else {
                    state.focus(showID: existingCurrent?.id)
                }
                notificationState = state
            } else {
                notificationState = nil
            }
            try modelContext.save()
            return AddShowPersistenceResult(
                outcome: .footprint,
                notificationState: notificationState
            )
        case .future where existingCurrent != nil:
            if let existingCurrent,
               selections.first?.selectedShowID != existingCurrent.id {
                let selection = selections.first ?? CurrentShowSelection()
                if selections.isEmpty {
                    modelContext.insert(selection)
                }
                selection.preserveAutomaticallySelected(showID: existingCurrent.id)
            }
            try modelContext.save()
            return AddShowPersistenceResult(outcome: .future, notificationState: nil)
        case .future, .live:
            let selection = selections.first ?? CurrentShowSelection()
            if selections.isEmpty {
                modelContext.insert(selection)
            }
            if lifecycle == .live {
                selection.select(showID: show.id)
            } else {
                selection.preserveAutomaticallySelected(showID: show.id)
            }

            let notificationState = notificationStates.first
                ?? NotificationSchedulingState(focusedShowID: show.id)
            if notificationStates.isEmpty {
                modelContext.insert(notificationState)
            } else {
                notificationState.focus(showID: show.id)
            }

            try modelContext.save()
            return AddShowPersistenceResult(
                outcome: lifecycle == .live ? .current : .future,
                notificationState: notificationState
            )
        }
    }
}
