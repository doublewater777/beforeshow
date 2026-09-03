import Foundation
import SwiftData

/// Single startup entry point for lightweight development-store repairs.
/// Feature code may keep its own defensive invariant checks, but app startup must
/// never scatter migration calls across multiple SwiftUI lifecycle callbacks.
@MainActor
enum AppPersistenceMigrationRunner {
    static func run(in modelContext: ModelContext, now: Date = Date()) {
        ShowCreationOriginMigration.migrateIfNeeded(in: modelContext)
        CurrentShowOwnershipMigration.migrateIfNeeded(in: modelContext, now: now)
        NotificationPortfolioMigration.migrateIfNeeded(in: modelContext)
        AppleMusicArtistIdentityMigration.migrateIfNeeded(in: modelContext)
    }
}

/// Gives pre-field rows an explicit show creation origin.
enum ShowCreationOriginMigration {
    static func migrateIfNeeded(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }

        guard resolveUnresolvedOrigins(in: shows) else { return }
        try? modelContext.save()
    }

    /// Kept public to the module because Companion import calls this immediately
    /// before merge/create, closing the race between share acceptance and startup.
    @discardableResult
    static func resolveUnresolvedOrigins(in shows: [Show]) -> Bool {
        var didChange = false
        for show in shows where show.hasUnresolvedCreationOrigin {
            show.creationOrigin = .user
            didChange = true
        }
        return didChange
    }
}

/// Converts the old time-owned Current Show state into one durable user-owned choice.
/// After this runs, `isManual == true` is a marker that runtime must never replace
/// the selection merely because time advanced.
@MainActor
enum CurrentShowOwnershipMigration {
    static func migrateIfNeeded(
        in modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let shows = try? modelContext.fetch(FetchDescriptor<Show>()),
              let rawSelections = try? modelContext.fetch(FetchDescriptor<CurrentShowSelection>()) else {
            return
        }

        let selections = rawSelections.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let canonical = selections.first
        for duplicate in selections.dropFirst() {
            modelContext.delete(duplicate)
        }

        if let canonical {
            if canonical.isManual == true,
               let selectedShowID = canonical.selectedShowID,
               shows.contains(where: { $0.id == selectedShowID }) {
                if selections.count > 1 {
                    try? modelContext.save()
                }
                return
            }

            let resolvedShow: Show?
            if canonical.isManual == false {
                resolvedShow = LegacyCurrentShowSelectionResolver(
                    calendar: calendar
                ).selectCurrentShow(
                    from: shows,
                    automaticSelection: canonical,
                    now: now
                )
            } else {
                resolvedShow = InitialCurrentShowPolicy(calendar: calendar)
                    .candidate(from: shows, now: now)
            }

            if let resolvedShow {
                canonical.select(showID: resolvedShow.id)
            } else {
                canonical.clearSelection()
            }
        } else if let candidate = InitialCurrentShowPolicy(calendar: calendar)
            .candidate(from: shows, now: now) {
            modelContext.insert(CurrentShowSelection(selectedShowID: candidate.id))
        }

        try? modelContext.save()
    }
}

/// One-time bridge from the old single-focus notification world.
/// Existing shows must not suddenly mint anticipation backfill after upgrading to
/// the portfolio scheduler. New Add Show rows are minted explicitly by the add flow.
@MainActor
enum NotificationPortfolioMigration {
    private static let currentVersion = 1

    static func migrateIfNeeded(in modelContext: ModelContext) {
        guard let shows = try? modelContext.fetch(FetchDescriptor<Show>()),
              let state = try? NotificationSchedulingStateStore.canonicalize(in: modelContext) else {
            return
        }
        guard (state.portfolioMigrationVersion ?? 0) < currentVersion else { return }

        var minted = Set(state.backfillMintedShowIDs ?? [])
        minted.formUnion(shows.map(\.id))
        state.backfillMintedShowIDs = Array(minted)
        state.focusedShowID = nil
        state.portfolioMigrationVersion = currentVersion
        state.updatedAt = Date()
        try? modelContext.save()
    }
}

/// Snapshot of the pre-v1.1 runtime selector. It exists only to preserve what an
/// automatic development-store row would have displayed at upgrade time.
private struct LegacyCurrentShowSelectionResolver {
    let postShowRetentionDays: Int
    let calendar: Calendar

    init(postShowRetentionDays: Int = 3, calendar: Calendar = .current) {
        self.postShowRetentionDays = postShowRetentionDays
        self.calendar = calendar
    }

    func selectCurrentShow(
        from shows: [Show],
        automaticSelection: CurrentShowSelection,
        now: Date
    ) -> Show? {
        let automaticallySelectableShows = shows
            .map { show in
                (
                    show,
                    CurrentShowTimeState(
                        show: show,
                        calendar: calendar,
                        now: now,
                        retentionDays: postShowRetentionDays
                    )
                )
            }
            .filter { show, state in isAutomaticallySelectable(show, state: state) }
            .sorted { first, second in
                let firstRank = automaticSelectionRank(for: first.0, state: first.1, now: now)
                let secondRank = automaticSelectionRank(for: second.0, state: second.1, now: now)
                if firstRank != secondRank { return firstRank < secondRank }

                let firstDistance = abs(first.1.dayDistance)
                let secondDistance = abs(second.1.dayDistance)
                if firstDistance == secondDistance {
                    return first.1.effectiveDate < second.1.effectiveDate
                }
                return firstDistance < secondDistance
            }
            .map { show, _ in show }

        if let automaticallySelected = automaticallySelectableShows.first,
           isActuallyLive(timeState(for: automaticallySelected, now: now), now: now) {
            return automaticallySelected
        }

        if let selectedShowID = automaticSelection.selectedShowID,
           let selectedShow = shows.first(where: { $0.id == selectedShowID }),
           isAutomaticallySelectable(
               selectedShow,
               state: timeState(for: selectedShow, now: now)
           ) {
            return selectedShow
        }

        return automaticallySelectableShows.first
    }

    private func timeState(for show: Show, now: Date) -> CurrentShowTimeState {
        CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: now,
            retentionDays: postShowRetentionDays
        )
    }

    private func isAutomaticallySelectable(
        _ show: Show,
        state: CurrentShowTimeState
    ) -> Bool {
        if show.wasAddedAsHistorical == true { return false }
        if state.kind == .ended { return show.endedAt == nil }
        return state.isAutomaticallySelectable
    }

    private func automaticSelectionRank(
        for show: Show,
        state: CurrentShowTimeState,
        now: Date
    ) -> Int {
        if isActuallyLive(state, now: now) { return 0 }
        if state.kind == .dayEnded
            || ((state.kind == .postShow || state.kind == .ended) && show.endedAt == nil) {
            return 1
        }
        switch state.kind {
        case .today, .before: return 2
        case .dayEnded: return 1
        case .postShow: return 3
        case .ended, .canceled, .postponed: return 4
        }
    }

    private func isActuallyLive(_ state: CurrentShowTimeState, now: Date) -> Bool {
        guard state.kind == .today,
              let start = state.effectiveStartTime,
              let boundary = state.endBoundary else {
            return false
        }
        return now >= start && now < boundary
    }
}
