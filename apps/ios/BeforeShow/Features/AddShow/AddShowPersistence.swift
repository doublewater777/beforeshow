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
    /// The state carries permission history plus a transient just-added backfill
    /// candidate. It is no longer a notification focus.
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
        selections _: [CurrentShowSelection],
        notificationStates _: [NotificationSchedulingState],
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> AddShowPersistenceResult {
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

        switch lifecycle {
        case .ended:
            if show.endedAt == nil {
                show.markAddedAsHistorical()
                try modelContext.save()
                return AddShowPersistenceResult(
                    outcome: .footprint,
                    notificationState: nil
                )
            }

            // A confirmed ended import can still own a future after-show reminder.
            // Stage it as a one-shot portfolio backfill candidate without changing
            // the user's Current Show.
            let state = try NotificationSchedulingStateStore.canonicalize(in: modelContext)
            state.stageBackfillCandidate(showID: show.id)
            try modelContext.save()
            return AddShowPersistenceResult(
                outcome: .footprint,
                notificationState: state
            )

        case .future, .live:
            let becameCurrent = existingCurrent == nil
            if becameCurrent {
                _ = try selectionStore.select(showID: show.id)
            }

            // Every newly added upcoming/live show gets its own notification nodes.
            // `focusedShowID` is only a crash-safe hand-off to the portfolio reconciler.
            let state = try NotificationSchedulingStateStore.canonicalize(in: modelContext)
            state.stageBackfillCandidate(showID: show.id)
            try modelContext.save()

            return AddShowPersistenceResult(
                outcome: lifecycle == .live && becameCurrent ? .current : .future,
                notificationState: state
            )
        }
    }
}
