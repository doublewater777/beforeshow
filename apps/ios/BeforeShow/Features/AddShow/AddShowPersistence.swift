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

struct AddShowPersistenceResult {
    let outcome: AddShowSaveOutcome
    /// Permission history for a show that can still own future notification nodes.
    let notificationState: NotificationSchedulingState?
    let committedState: CurrentShowCommittedState
}

enum AddShowPersistenceError: Error, Equatable {
    case duplicateShow(existingShowID: UUID)
}

@MainActor
enum AddShowPersistenceCoordinator {
    static func persist(
        _ show: Show,
        lifecycle: AddShowFinalLifecycle,
        setAsCurrent: Bool = false,
        selections _: [CurrentShowSelection] = [],
        notificationStates _: [NotificationSchedulingState] = [],
        in modelContext: ModelContext,
        now: Date = Date(),
        effects: CurrentShowPostCommitEffects = .live,
        beforePostCommit: @MainActor (AddShowSaveOutcome) -> Void = { _ in }
    ) async throws -> AddShowPersistenceResult {
        let persistedShows = try modelContext.fetch(FetchDescriptor<Show>())
        if let duplicate = ShowDuplicateMatcher.firstDuplicate(of: show, in: persistedShows) {
            throw AddShowPersistenceError.duplicateShow(existingShowID: duplicate.id)
        }

        let selectionStore = CurrentShowSelectionStore(modelContext: modelContext)
        let existingSelection = try selectionStore.canonicalSelection()
        let existingCurrent = CurrentShowSession().selectCurrentShow(
            from: persistedShows,
            manualSelection: existingSelection,
            now: now
        )

        modelContext.insert(show)

        let outcome: AddShowSaveOutcome
        let notificationState: NotificationSchedulingState?
        switch lifecycle {
        case .ended:
            // Historical shows still belong to Footprints, but Current Show is a
            // durable user-owned selection rather than a lifecycle filter. When
            // there is no valid Current yet, let the newly added historical show
            // bootstrap it; otherwise never steal the existing selection.
            if setAsCurrent || existingCurrent == nil {
                _ = try selectionStore.select(showID: show.id)
            }

            if show.endedAt == nil {
                show.markAddedAsHistorical()
                outcome = .footprint
                notificationState = nil
            } else {
                // A confirmed ended import can still own a future after-show reminder.
                notificationState = try NotificationSchedulingStateStore.canonicalize(in: modelContext)
                outcome = .footprint
            }

        case .future, .live:
            let becameCurrent = setAsCurrent || (existingCurrent == nil)
            if becameCurrent {
                _ = try selectionStore.select(showID: show.id)
            }

            // Every newly added upcoming/live show gets its own notification nodes.
            notificationState = try NotificationSchedulingStateStore.canonicalize(in: modelContext)
            outcome = setAsCurrent ? .current : (lifecycle == .live && becameCurrent ? .current : .future)
        }

        let committedState: CurrentShowCommittedState
        do {
            try ShowMutationCoordinator.reconcileListening(in: modelContext, now: now)
            try modelContext.save()
            let shows = try modelContext.fetch(FetchDescriptor<Show>())
            let selection = try selectionStore.canonicalSelection()
            committedState = CurrentShowCommittedState(
                currentShow: CurrentShowSession().selectCurrentShow(
                    from: shows,
                    manualSelection: selection,
                    now: now
                ),
                shows: shows,
                selection: selection
            )
        } catch {
            modelContext.rollback()
            throw error
        }

        beforePostCommit(outcome)
        _ = await ShowMutationCoordinator.syncPostCommit(
            committedState,
            in: modelContext,
            effects: effects
        )
        return AddShowPersistenceResult(
            outcome: outcome,
            notificationState: notificationState,
            committedState: committedState
        )
    }
}
