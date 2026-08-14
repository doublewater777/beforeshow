import Foundation
import SwiftData

@MainActor
final class ArtistWarmupCoordinator {
    private let service: ArtistWarmupCatalogProviding & ArtistWarmupPlaying
    private let context: ModelContext
    private var listeningEvidence = WarmupListeningEvidence()

    init(
        service: ArtistWarmupCatalogProviding & ArtistWarmupPlaying,
        context: ModelContext
    ) {
        self.service = service
        self.context = context
    }

    @discardableResult
    func refreshCatalog(artistID: String, now: Date = Date()) async throws -> ArtistCatalogSnapshot {
        let catalog = await service.enumerateAudioCatalog(artistID: artistID)
        let snapshot: ArtistCatalogSnapshot
        switch catalog.completeness {
        case .complete:
            snapshot = ArtistCatalogSnapshot.complete(
                artistID: artistID,
                songIDs: catalog.songIDsForFamiliarity,
                fetchedAt: now
            )
        case .partial:
            snapshot = ArtistCatalogSnapshot.failed(artistID: artistID, fetchedAt: now)
        }

        if let existing = try fetchSnapshot(artistID: artistID) {
            context.delete(existing)
        }
        context.insert(snapshot)
        replaceCatalogSongs(catalog.songs)
        try context.save()
        return snapshot
    }

    func warmupQueue(showID: UUID, scope: ArtistWarmupQueueScope) throws -> [ArtistWarmupCatalogSong] {
        let artists = try context.fetch(
            FetchDescriptor<ShowArtist>(
                predicate: #Predicate { $0.showID == showID }
            )
        )
        .filter { $0.isConnectedToAppleMusic }

        let tracks = artists.map { artist in
            ArtistWarmupTrack(
                id: artist.appleMusicArtistID ?? artist.id.uuidString,
                artistID: artist.appleMusicArtistID ?? artist.id.uuidString,
                interest: artist.interest
            )
        }
        let orderedArtistIDs = ArtistWarmupQueueBuilder.build(from: tracks, scope: scope).map(\.artistID)
        let songs = try context.fetch(FetchDescriptor<CatalogSong>())
        let heardIDs = Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).map(\.songID))
        let songsByArtist = Dictionary(grouping: songs) { song in
            song.performingArtistIDs.first ?? "unknown"
        }
        return orderedArtistIDs.flatMap { artistID in
            let artistSongs = songsByArtist[artistID, default: []]
            let unheard = artistSongs.filter { !heardIDs.contains($0.appleMusicSongID) }
            let heard = artistSongs.filter { heardIDs.contains($0.appleMusicSongID) }
            return (unheard + heard).map { song in
                ArtistWarmupCatalogSong(
                    id: song.appleMusicSongID,
                    artistID: song.performingArtistIDs.first ?? "unknown",
                    title: song.title,
                    albumTitle: song.albumTitle,
                    artistName: song.performingArtistNames.first ?? song.title,
                    performerArtistIDs: song.performingArtistIDs,
                    performerNames: song.performingArtistNames,
                    duration: song.duration,
                    source: source(for: song),
                    previewFallbackURL: nil
                )
            }
        }
    }

    func captureEligibleOpeningSnapshots(now: Date = Date(), calendar: Calendar = .current) throws {
        let shows = try context.fetch(FetchDescriptor<Show>())
        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        guard let show = CurrentShowSession(calendar: calendar)
            .resolve(shows: shows, manualSelection: selections.first, now: now)?
            .show else {
            return
        }
        let service = ArtistWarmupSnapshotService(context: context)
        _ = try service.captureOpeningSnapshots(for: show, now: now, calendar: calendar)
        try context.save()
    }

    func playbackSample(
        songID: String,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool,
        isPreview: Bool
    ) -> WarmupListeningEvidence.PlaybackSample {
        WarmupListeningEvidence.PlaybackSample(
            songID: songID,
            source: isPreview ? .appleMusicPreview : .appleMusicFullPlayback,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    @discardableResult
    func ingestPlaybackSample(
        _ sample: WarmupListeningEvidence.PlaybackSample,
        now: Date = Date()
    ) throws -> Bool {
        switch listeningEvidence.update(sample) {
        case let .heard(songID):
            try upsertFamiliarity(songID: songID, heardAt: now, source: .auto)
            try context.save()
            return true
        case .none, .manuallyMarked:
            return false
        }
    }

    private func fetchSnapshot(artistID: String) throws -> ArtistCatalogSnapshot? {
        try context.fetch(
            FetchDescriptor<ArtistCatalogSnapshot>(
                predicate: #Predicate { $0.artistID == artistID }
            )
        ).first
    }

    private func replaceCatalogSongs(_ songs: [ArtistWarmupCatalogSong]) {
        for song in songs {
            if let existing = try? fetchCatalogSong(id: song.id) {
                context.delete(existing)
            }

            context.insert(CatalogSong(
                appleMusicSongID: song.id,
                title: song.title,
                albumTitle: song.albumTitle,
                artworkURL: nil,
                duration: song.duration,
                performingArtistIDs: Array(Set(song.performerArtistIDs + [song.artistID])),
                performingArtistNames: song.performerNames.isEmpty ? [song.artistName] : song.performerNames,
                category: category(for: song.source)
            ))
        }
    }

    private func fetchCatalogSong(id: String) throws -> CatalogSong? {
        try context.fetch(
            FetchDescriptor<CatalogSong>(
                predicate: #Predicate { $0.appleMusicSongID == id }
            )
        ).first
    }

    private func category(for source: ArtistWarmupCatalogSource) -> CatalogSongCategory {
        switch source {
        case .topSongs, .album:
            .album
        case .single:
            .single
        case .compilationAlbum:
            .collaboration
        }
    }

    private func source(for song: CatalogSong) -> ArtistWarmupCatalogSource {
        switch song.category {
        case .album:
            .album(song.albumTitle ?? song.appleMusicSongID)
        case .single:
            .single(song.albumTitle ?? song.appleMusicSongID)
        case .collaboration:
            .compilationAlbum(song.albumTitle ?? song.appleMusicSongID)
        }
    }

    private func upsertFamiliarity(
        songID: String,
        heardAt: Date,
        source: SongFamiliaritySource
    ) throws {
        if let existing = try context.fetch(
            FetchDescriptor<SongFamiliarityRecord>(
                predicate: #Predicate { $0.songID == songID }
            )
        ).first {
            existing.update(heardAt: heardAt, source: source)
            return
        }

        context.insert(SongFamiliarityRecord(songID: songID, heardAt: heardAt, source: source))
    }
}
