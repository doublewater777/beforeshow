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
    let reconcileNotifications: @MainActor (ModelContext) async -> Bool
    let syncWidget: @MainActor ([Show], CurrentShowSelection?) -> Bool

    static let live = CurrentShowPostCommitEffects(
        reconcileNotifications: { modelContext in
            await LocalNotificationCenter.shared.reconcilePortfolio(
                in: modelContext
            )
        },
        syncWidget: { shows, selection in
            WidgetDataSync.sync(shows: shows, manualSelection: selection)
        }
    )

    /// Tests that only care about the saved 现场 pass this so they do not touch notifications or widgets.
    static let skipped = CurrentShowPostCommitEffects(
        reconcileNotifications: { _ in true },
        syncWidget: { _, _ in true }
    )
}

@MainActor
struct CurrentShowCommittedState {
    let currentShow: Show?
    let shows: [Show]
    let selection: CurrentShowSelection?
}

/// Save / show state / cross-surface sync for a single `Show`.
/// Current Show ownership is durable and independent from notification scheduling.
enum ShowMutationCoordinator {
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
        selections _: [CurrentShowSelection],
        notificationStates _: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        now: Date = Date()
    ) throws -> CurrentShowCommittedState {
        try reconcileListening(in: modelContext, now: now)
        let store = CurrentShowSelectionStore(modelContext: modelContext)
        let selection = try store.bootstrapIfNeeded(
            shows: shows,
            now: now,
            policy: InitialCurrentShowPolicy(calendar: session.calendar)
        )
        let currentShow = session.selectCurrentShow(
            from: shows,
            manualSelection: selection,
            now: now
        )
        try modelContext.save()

        return CurrentShowCommittedState(
            currentShow: currentShow,
            shows: shows,
            selection: selection
        )
    }

    @MainActor
    static func reconcileListening(
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        _ = try ListeningShowLifecycleCoordinator.reconcileStoredState(
            in: modelContext,
            now: now
        )
    }

    @MainActor
    static func syncPostCommit(
        _ committedState: CurrentShowCommittedState,
        in modelContext: ModelContext,
        effects: CurrentShowPostCommitEffects = .live
    ) async -> Bool {
        let notificationContext = ModelContext(modelContext.container)
        let didSyncNotifications = await effects.reconcileNotifications(notificationContext)
        let didSyncWidget = effects.syncWidget(
            committedState.shows,
            committedState.selection
        )
        return didSyncNotifications && didSyncWidget
    }

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
            try show.setClosingRitual(
                rating: rating,
                note: note,
                markCeremonyCompleted: true
            )
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
        let store = CurrentShowSelectionStore(modelContext: modelContext)
        do {
            if let showID {
                _ = try store.select(showID: showID)
            } else {
                _ = try store.clear()
            }
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

}

extension Show {
    /// Persist the private dispersal draft without affecting lifecycle state.
    func setClosingRitual(
        rating: Int?,
        note: String?,
        markCeremonyCompleted: Bool = false
    ) throws {
        if let rating, !(1...5).contains(rating) {
            throw ShowValidationError.ratingOutOfRange
        }

        let normalized = try Self.normalizeClosingNote(note)
        let completesCeremony = markCeremonyCompleted && !hasCompletedDispersalCeremony
        guard self.rating != rating
                || closingNote != normalized
                || completesCeremony else {
            return
        }

        self.rating = rating
        closingNote = normalized
        if markCeremonyCompleted {
            hasCompletedDispersalCeremony = true
        }
        updatedAt = Date()
    }

    static func normalizeClosingNote(_ text: String?) throws -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= 500 else {
            throw ShowValidationError.closingNoteTooLong
        }
        return normalized
    }
}
