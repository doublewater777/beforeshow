import Foundation
import SwiftData

@MainActor
enum ListeningShowLifecycleCoordinator {
    @discardableResult
    static func reconcileStoredState(
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> Bool {
        let shows = try modelContext.fetch(FetchDescriptor<Show>())
        let baselines = try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
        let tiers = try modelContext.fetch(FetchDescriptor<ShowOpeningArtistTier>())
        let preferences = try modelContext.fetch(FetchDescriptor<ShowArtistListeningPreference>())
        let showByID = Dictionary(uniqueKeysWithValues: shows.map { ($0.id, $0) })
        var invalidatedShowIDs = Set<UUID>()
        var didChange = false

        for baseline in baselines {
            guard let show = showByID[baseline.showID] else { continue }
            if invalidatesOpeningBaseline(show: show, now: now) {
                modelContext.delete(baseline)
                invalidatedShowIDs.insert(show.id)
                didChange = true
            }
        }

        for tier in tiers {
            if invalidatedShowIDs.contains(tier.showID) {
                modelContext.delete(tier)
                didChange = true
                continue
            }
            guard let show = showByID[tier.showID] else { continue }
            let currentArtistIDs = Set(show.artists.compactMap(\.appleMusicArtistID))
            if !currentArtistIDs.contains(tier.artistID) {
                modelContext.delete(tier)
                didChange = true
            }
        }

        for preference in preferences {
            guard let show = showByID[preference.showID] else { continue }
            let currentArtistIDs = Set(show.artists.compactMap(\.appleMusicArtistID))
            if !currentArtistIDs.contains(preference.artistID) {
                modelContext.delete(preference)
                didChange = true
            }
        }

        return didChange
    }

    private static func invalidatesOpeningBaseline(show: Show, now: Date) -> Bool {
        if show.changeStatus == .canceled { return true }
        if show.changeStatus == .postponed, show.postponedDate == nil { return true }

        let timeState = CurrentShowTimeState(show: show, now: now)
        if let effectiveStart = timeState.effectiveStartTime, effectiveStart > now {
            return true
        }
        return false
    }
}
