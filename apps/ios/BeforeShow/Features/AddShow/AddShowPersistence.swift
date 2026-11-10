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

/// 新加的现场何时接管当前现场（不论原选择是自动还是手动）：
/// 用户确认还在现场；或原当前现场已散场（含停留期）/ 已取消 / 不存在。
/// 原当前现场还没开场或仍在进行（含音乐节两天之间）时不动。
enum AddShowCurrentShowPolicy {
    enum Takeover: Equatable {
        case userConfirmedLive
        case replacesFinished
        case keep
    }

    static func takeover(
        lifecycle: AddShowFinalLifecycle,
        previousCurrent: Show?,
        now: Date,
        calendar: Calendar = .current
    ) -> Takeover {
        switch lifecycle {
        case .ended: return .keep
        case .live: return .userConfirmedLive
        case .future: break
        }
        guard let previousCurrent else { return .replacesFinished }
        if previousCurrent.endedAt != nil { return .replacesFinished }
        switch CurrentShowTimeState(show: previousCurrent, calendar: calendar, now: now).kind {
        case .postShow, .ended, .canceled:
            return .replacesFinished
        case .before, .today, .dayEnded, .postponed:
            return .keep
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
        let previousCurrent = CurrentShowSession().selectCurrentShow(
            from: persistedShows,
            manualSelection: try selectionStore.canonicalSelection(),
            now: now
        )
        modelContext.insert(show)

        let notificationState: NotificationSchedulingState?
        switch lifecycle {
        case .ended:
            // A show imported through the historical path cannot take over Current,
            // even when the user supplied an actual end time.
            show.markAddedAsHistorical()
            notificationState = show.endedAt == nil
                ? nil
                : try NotificationSchedulingStateStore.canonicalize(in: modelContext)
        case .future, .live:
            notificationState = try NotificationSchedulingStateStore.canonicalize(in: modelContext)
        }

        // Historical imports must never become the automatic Current Show.
        // Reconcile the complete portfolio so an earlier show can replace an
        // automatic upcoming selection, but not a manual one.
        let availableShows = try modelContext.fetch(FetchDescriptor<Show>())
        var selection = try selectionStore.bootstrapIfNeeded(shows: availableShows, now: now)
        switch AddShowCurrentShowPolicy.takeover(
            lifecycle: lifecycle,
            previousCurrent: previousCurrent,
            now: now
        ) {
        case .userConfirmedLive:
            selection = try selectionStore.select(showID: show.id)
        case .replacesFinished:
            let record = try selection ?? selectionStore.select(showID: show.id)
            record.selectAutomatically(showID: show.id)
            selection = record
        case .keep:
            break
        }
        let resolved = CurrentShowSession().selectCurrentShow(
            from: availableShows, manualSelection: selection, now: now
        )
        let outcome: AddShowSaveOutcome = lifecycle == .ended
            ? .footprint
            : (resolved?.id == show.id ? .current : .future)

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
