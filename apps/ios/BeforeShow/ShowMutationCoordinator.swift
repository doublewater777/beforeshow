import Foundation
import SwiftData

/// Conservative content identity used only by the user-facing add-show flow.
/// A match requires the same normalized name and venue-local start minute; optional
/// location / artist fields only veto a match when both sides provide conflicting data.
enum ShowDuplicateMatcher {
    private struct TimingSignature: Equatable {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
    }

    static func firstDuplicate(of candidate: Show, in shows: [Show]) -> Show? {
        shows.first { isDuplicate(candidate, $0) }
    }

    static func isDuplicate(_ lhs: Show, _ rhs: Show) -> Bool {
        guard normalized(lhs.name) == normalized(rhs.name),
              timingSignature(lhs) == timingSignature(rhs) else {
            return false
        }

        if let lhsVenue = normalized(lhs.venueName),
           let rhsVenue = normalized(rhs.venueName),
           lhsVenue != rhsVenue {
            return false
        }
        if let lhsCity = normalized(lhs.city),
           let rhsCity = normalized(rhs.city),
           lhsCity != rhsCity {
            return false
        }

        let lhsArtists = Set(lhs.artistNames.compactMap { normalized($0) })
        let rhsArtists = Set(rhs.artistNames.compactMap { normalized($0) })
        if !lhsArtists.isEmpty,
           !rhsArtists.isEmpty,
           lhsArtists.isDisjoint(with: rhsArtists) {
            return false
        }

        return true
    }

    private static func timingSignature(_ show: Show) -> TimingSignature {
        let calendar = show.timingCalendar()
        let day = calendar.dateComponents([.year, .month, .day], from: show.date)
        let clock = calendar.dateComponents([.hour, .minute], from: show.startTime)
        return TimingSignature(
            year: day.year ?? 0,
            month: day.month ?? 0,
            day: day.day ?? 0,
            hour: clock.hour ?? 0,
            minute: clock.minute ?? 0
        )
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let value = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return value.isEmpty ? nil : value
    }
}

@MainActor
struct CurrentShowPostCommitEffects {
    let applyNotificationFocus: @MainActor (Show?, ModelContext) async -> Bool
    let syncWidget: @MainActor ([Show], CurrentShowSelection?) -> Bool

    static let live = CurrentShowPostCommitEffects(
        applyNotificationFocus: { show, modelContext in
            await LocalNotificationCenter.shared.applyFocusChange(to: show, in: modelContext)
        },
        syncWidget: { shows, selection in
            WidgetDataSync.sync(shows: shows, manualSelection: selection)
        }
    )
}

@MainActor
struct CurrentShowCommittedState {
    let currentShow: Show?
    let shows: [Show]
    let manualSelection: CurrentShowSelection?
}

/// Save / 现场状态 / notification-sync for a single `Show`.
/// Detail screen and draft editor both call through here so apply + status +
/// reschedule stay consistent and unit-testable without a SwiftUI view.
enum ShowMutationCoordinator {
    /// Apply draft fields to an existing show, persist, then reschedule notifications
    /// for the current focus. Throws on draft apply / save failure (after rollback).
    /// Returns whether notification reschedule succeeded.
    @MainActor
    static func applyDraft(
        _ draft: ShowDraft,
        to show: Show,
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        effects: CurrentShowPostCommitEffects = .live
    ) async throws -> Bool {
        try await commitCurrentShowChange(
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session,
            effects: effects
        ) {
            try show.apply(draft)
        }
    }

    /// Commit one model change together with the derived current-show selection and
    /// notification focus. External notification/widget work starts only after save.
    @MainActor
    static func commitCurrentShowChange(
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        effects: CurrentShowPostCommitEffects = .live,
        mutation: () throws -> Void
    ) async throws -> Bool {
        do {
            try mutation()
            let committedState = try commitCurrentShowState(
                shows: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                session: session
            )
            return await syncPostCommit(
                committedState,
                in: modelContext,
                effects: effects
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @MainActor
    static func commitCurrentShowState(
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession()
    ) throws -> CurrentShowCommittedState {
        let effectiveSelections = selections.isEmpty
            ? try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            : selections
        reconcileManualSelection(
            shows: shows,
            selections: effectiveSelections,
            session: session
        )

        let currentShow = session.selectCurrentShow(
            from: shows,
            manualSelection: effectiveSelections.first
        )
        let effectiveNotificationStates = notificationStates.isEmpty
            ? try modelContext.fetch(FetchDescriptor<NotificationSchedulingState>())
            : notificationStates
        updateNotificationFocus(
            showID: currentShow?.id,
            notificationStates: effectiveNotificationStates,
            in: modelContext
        )
        try modelContext.save()

        return CurrentShowCommittedState(
            currentShow: currentShow,
            shows: shows,
            manualSelection: effectiveSelections.first
        )
    }

    @MainActor
    static func syncPostCommit(
        _ committedState: CurrentShowCommittedState,
        in modelContext: ModelContext,
        effects: CurrentShowPostCommitEffects = .live
    ) async -> Bool {
        let notificationContext = ModelContext(modelContext.container)
        let didSyncNotifications = await effects.applyNotificationFocus(
            committedState.currentShow,
            notificationContext
        )
        let didSyncWidget = effects.syncWidget(
            committedState.shows,
            committedState.manualSelection
        )
        return didSyncNotifications && didSyncWidget
    }

    /// Apply a status mutation (postpone / cancel / restore), clear manual current
    /// when the resulting show is no longer eligible, persist, then reschedule.
    /// Returns toast tone + message.
    @MainActor
    static func updateStatus(
        show: Show,
        message: String,
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        effects: CurrentShowPostCommitEffects = .live,
        mutation: () -> Void
    ) async -> ShowStatusActionResult {
        do {
            let didSync = try await commitCurrentShowChange(
                shows: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                session: session,
                effects: effects,
                mutation: mutation
            )
            let presentedMessage = didSync ? message : BSLocalization.format("%@，同步暂未更新", message)
            return ShowStatusActionResult(
                tone: didSync ? .success : .neutral,
                message: presentedMessage
            )
        } catch {
            return ShowStatusActionResult(tone: .failure, message: BSLocalization.text("状态没有保存，请重试"))
        }
    }

    /// Persist a manual current-show selection together with its notification focus,
    /// then refresh notification and widget surfaces from the committed state.
    @MainActor
    static func commitClosingRitual(
        rating: Int?,
        note: String?,
        show: Show,
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        effects: CurrentShowPostCommitEffects = .live
    ) async throws -> Bool {
        try await commitCurrentShowChange(
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session,
            effects: effects
        ) {
            try show.setClosingRitual(rating: rating, note: note)
        }
    }

    @MainActor
    static func selectCurrentShow(
        showID: UUID?,
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        effects: CurrentShowPostCommitEffects = .live
    ) async throws -> Bool {
        var effectiveSelections = selections
        if effectiveSelections.isEmpty {
            effectiveSelections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
        }

        if let selection = effectiveSelections.first {
            if let showID {
                selection.select(showID: showID)
            } else {
                selection.clearManualSelection()
            }
        } else if let showID {
            let selection = CurrentShowSelection(selectedShowID: showID)
            modelContext.insert(selection)
            effectiveSelections = [selection]
        }

        do {
            let committedState = try commitCurrentShowState(
                shows: shows,
                selections: effectiveSelections,
                notificationStates: notificationStates,
                in: modelContext,
                session: session
            )
            return await syncPostCommit(
                committedState,
                in: modelContext,
                effects: effects
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func reconcileManualSelection(
        shows: [Show],
        selections: [CurrentShowSelection],
        session: CurrentShowSession = CurrentShowSession(),
        now: Date = Date()
    ) {
        guard let selection = selections.first,
              let selectedShowID = selection.selectedShowID else {
            return
        }

        guard let selectedShow = shows.first(where: { $0.id == selectedShowID }),
              session.isManuallySelectable(selectedShow, now: now) else {
            selection.clearManualSelection()
            return
        }
    }

    @MainActor
    private static func updateNotificationFocus(
        showID: UUID?,
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext
    ) {
        if let notificationState = notificationStates.first {
            notificationState.focus(showID: showID)
        } else if showID != nil {
            modelContext.insert(NotificationSchedulingState(focusedShowID: showID))
        }
    }
}
