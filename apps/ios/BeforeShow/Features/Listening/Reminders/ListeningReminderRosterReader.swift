import Foundation
import SwiftData

@MainActor
enum ListeningReminderRosterReader {
    static func read(show: Show, in context: ModelContext) throws -> ListeningReminderRoster {
        let showID = show.id
        let excluded = Set(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>(
            predicate: #Predicate { $0.showID == showID && $0.isExcluded })).map(\.artistID))
        let performances = (show.timetable?.orderedDays ?? []).flatMap(\.performances)
        let catalog = ListeningCatalogProjection(context: context, catalogStore: ListeningCatalogStore(modelContext: context))
        try catalog.refresh(artistIDs: show.artists.compactMap(\.appleMusicArtistID) + performances.compactMap(\.appleMusicArtistID))
        let slots = show.artists.enumerated().filter {
            !excluded.contains($0.element.appleMusicArtistID ?? "unconnected-\($0.offset)")
        }
        func value(_ disc: ListeningDisc) -> ListeningReminderRoster.Disc {
            .init(id: disc.id, title: disc.title)
        }
        let artists = slots.map { index, slot in
            let id = slot.appleMusicArtistID ?? "unconnected-\(index)"
            let discs = catalog.artists[id]?.albums ?? []
            let albums = discs.filter { $0.origin == .album && $0.isSingle != true && !$0.tracks.isEmpty }
                .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
            let featured = discs.first { if case .featuredPlaylist = $0.origin { return true }; return false }
            return ListeningReminderRoster.Artist(id: id, name: slot.name,
                isConnected: slot.appleMusicArtistID != nil, albums: albums.map(value), featuredPlaylist: featured.map(value))
        }
        var wantedStarts: [String: Date] = [:]
        for performance in performances where performance.isInterested {
            guard let id = performance.appleMusicArtistID else { continue }
            wantedStarts[id] = min(wantedStarts[id] ?? .distantFuture, performance.startsAt)
        }
        let ordered = artists.enumerated().sorted { lhs, rhs in
            switch (wantedStarts[lhs.element.id], wantedStarts[rhs.element.id]) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        func topTracks(_ id: String) -> [ListeningDiscTrack] {
            excluded.contains(id) ? [] : catalog.artists[id]?.top ?? []
        }
        let compilations = ListeningCompilationAssembler.discs(
            showID: show.id, releaseDates: catalog.releaseDates,
            livePrograms: ListeningCompilationAssembler.livePrograms(for: show, topTracks: topTracks),
            artistTracks: artists.filter(\.isConnected).map { topTracks($0.id) })
        let heard = Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).compactMap {
            $0.actualListeningAt == nil ? nil : $0.songID
        })
        // Use the complete source track list, including tracks missing from a partial cache.
        var trackIDs = Dictionary(catalog.albums.map { ($0.appleMusicAlbumID, $0.orderedTrackIDs) },
                                  uniquingKeysWith: { first, _ in first })
        for snapshot in catalog.snapshots {
            for playlist in snapshot.featuredPlaylists { trackIDs[playlist.playlistID] = playlist.orderedTrackIDs }
        }
        for disc in compilations { trackIDs[disc.id] = disc.tracks.map(\.id) }
        let complete = Set(trackIDs.compactMap { id, tracks in
            !tracks.isEmpty && Set(tracks).isSubset(of: heard) ? id : nil
        })
        let calendar = show.timingCalendar()
        let opening = CurrentShowTimeState(show: show, calendar: calendar, now: .distantPast).effectiveDate
        let openingDay = show.timetable?.orderedDays.first { calendar.isDate($0.date, inSameDayAs: opening) }
        let wantedID = openingDay.map { "compilation-\(show.id)-wanted-\($0.id)" }
        let recent = try context.fetch(FetchDescriptor<ShowRecentListening>(predicate: #Predicate { $0.showID == showID }))
            .map(\.playedAt).max()
        return ListeningReminderRoster(artists: ordered, isMultiArtist: show.artists.count > 1,
            singalong: compilations.first { $0.id.hasSuffix("-singalong") }.map(value),
            latest: compilations.first { $0.id.hasSuffix("-latest") }.map(value),
            deepCuts: compilations.first { $0.id.hasSuffix("-deepCuts") }.map(value),
            wanted: compilations.first { $0.id == wantedID }.map(value),
            rehearsal: compilations.first { $0.id.hasSuffix("-rehearsal")
                || (show.artists.count == 1 && $0.id.contains("-stage-")) }.map(value),
            completedDiscIDs: complete, lastListenedAt: recent)
    }
}
