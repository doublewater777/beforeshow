import Foundation
import SwiftData

@MainActor
final class ListeningCatalogStore {
    private let modelContext: ModelContext
    private let service: any ListeningMusicCatalogServicing
    private let persistenceBoundary: ListeningCatalogPersistenceBoundary
    private(set) var revision = 0
    private var refreshTasks: [String: Task<Void, Error>] = [:]
    private var snapshotReadContext: ModelContext?
    private var revalidationTasks: [String: Task<Void, Never>] = [:]

    init(
        modelContext: ModelContext,
        service: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService()
    ) {
        self.modelContext = modelContext
        self.service = service
        persistenceBoundary = ListeningCatalogPersistenceBoundary(modelContainer: modelContext.container)
    }

    func cachedSnapshot(artistID: String) throws -> ArtistCatalogSnapshot? {
        let reader = ModelContext(modelContext.container)
        snapshotReadContext = reader
        return try reader.fetch(FetchDescriptor<ArtistCatalogSnapshot>(
            predicate: #Predicate { $0.artistID == artistID }
        )).first
    }

    /// Returns a last-good complete snapshot immediately when one exists. A stale
    /// snapshot remains usable while one background revalidation per artist runs.
    func loadArtistCatalog(
        artistID: String,
        now: Date = Date()
    ) async throws -> ArtistCatalogSnapshot {
        if let cached = try cachedSnapshot(artistID: artistID) {
            if ListeningCatalogRefreshPolicy.shouldRefresh(fetchedAt: cached.fetchedAt, now: now) {
                scheduleRevalidation(artistID: artistID, now: now)
            }
            return cached
        }
        return try await refreshArtistCatalog(artistID: artistID, now: now)
    }

    @discardableResult
    func refreshArtistCatalog(
        artistID: String,
        now: Date = Date()
    ) async throws -> ArtistCatalogSnapshot {
        if let task = refreshTasks[artistID] {
            try await task.value
            guard let snapshot = try cachedSnapshot(artistID: artistID) else {
                throw ListeningCatalogError.incompleteCatalog(artistID)
            }
            return snapshot
        }
        let task = Task { @MainActor in
            // Only complete payloads replace the last-good catalog. Both cold
            // loads and revalidation share the same off-main persistence path.
            let payload = try await service.fetchArtistCatalog(artistID: artistID, fetchedAt: now)
            _ = try await persistArtistCatalogBatch([payload])
        }
        refreshTasks[artistID] = task
        defer { refreshTasks[artistID] = nil }
        try await task.value
        guard let snapshot = try cachedSnapshot(artistID: artistID) else {
            throw ListeningCatalogError.incompleteCatalog(artistID)
        }
        return snapshot
    }

    /// Production core-catalog persistence boundary. All successful artist payloads
    /// from one coordinator pass cross this actor boundary together as Sendable values.
    /// Managed SwiftData objects never cross the boundary.
    func persistArtistCatalogBatch(
        _ payloads: [ListeningArtistCatalogPayload]
    ) async throws -> Set<String> {
        guard !payloads.isEmpty else { return [] }
        let persistedArtistIDs = try await persistenceBoundary.persistCore(payloads)
        revision += 1

        return persistedArtistIDs
    }

    /// Optional artist browsing data is persisted independently from the complete
    /// catalog denominator. A browse failure therefore cannot downgrade a last-good
    /// core snapshot or alter its completeness/freshness fields.
    func persistFeaturedPlaylists(
        _ payload: ListeningFeaturedPlaylistsPayload
    ) async throws -> Bool {
        let persisted = try await persistenceBoundary.persistFeaturedPlaylists(payload)
        if persisted { revision += 1 }
        return persisted
    }

    private func scheduleRevalidation(artistID: String, now: Date) {
        guard revalidationTasks[artistID] == nil else { return }
        revalidationTasks[artistID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.revalidationTasks[artistID] = nil }
            _ = try? await self.refreshArtistCatalog(artistID: artistID, now: now)
        }
    }
}

/// The outer actor delays creation of the SwiftData model actor until work actually
/// crosses this boundary. Because the lazy property is initialized from this actor's
/// executor instead of ListeningCatalogStore's MainActor initializer, the generated
/// ModelContext/DefaultSerialModelExecutor is not main-actor-bound.
private actor ListeningCatalogPersistenceBoundary {
    private let modelContainer: ModelContainer
    private lazy var persistenceActor = ListeningCatalogPersistenceActor(modelContainer: modelContainer)

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func persistCore(
        _ payloads: [ListeningArtistCatalogPayload]
    ) async throws -> Set<String> {
        try await persistenceActor.persistCore(payloads)
    }

    func persistFeaturedPlaylists(
        _ payload: ListeningFeaturedPlaylistsPayload
    ) async throws -> Bool {
        try await persistenceActor.persistFeaturedPlaylists(payload)
    }
}

@ModelActor
private actor ListeningCatalogPersistenceActor {
    func persistCore(
        _ payloads: [ListeningArtistCatalogPayload]
    ) throws -> Set<String> {
        do {
            return try ListeningCatalogBatchWriter.persistCore(payloads, in: modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func persistFeaturedPlaylists(
        _ payload: ListeningFeaturedPlaylistsPayload
    ) throws -> Bool {
        do {
            return try ListeningCatalogBatchWriter.persistFeaturedPlaylists(payload, in: modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private enum ListeningCatalogBatchWriter {
    static func persistCore(
        _ payloads: [ListeningArtistCatalogPayload],
        in modelContext: ModelContext
    ) throws -> Set<String> {
        guard !payloads.isEmpty else { return [] }

        let songIDs = Array(Set(payloads.flatMap { $0.songs.map(\.songID) }))
        let albumIDs = Array(Set(payloads.flatMap { $0.albums.map(\.albumID) }))
        let artistIDs = payloads.map(\.artistID)
        let existingSongs = try modelContext.fetch(FetchDescriptor<CatalogSong>(
            predicate: #Predicate { songIDs.contains($0.appleMusicSongID) }))
        let existingAlbums = try modelContext.fetch(FetchDescriptor<CatalogAlbum>(
            predicate: #Predicate { albumIDs.contains($0.appleMusicAlbumID) }))
        let existingSnapshots = try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>(
            predicate: #Predicate { artistIDs.contains($0.artistID) }))

        var songsByID = Dictionary(
            existingSongs.map { ($0.appleMusicSongID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var albumsByID = Dictionary(
            existingAlbums.map { ($0.appleMusicAlbumID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var snapshotsByID = Dictionary(
            existingSnapshots.map { ($0.artistID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var incomingSongs: [String: (ListeningCatalogSongPayload, Date)] = [:]
        var incomingAlbums: [String: (ListeningCatalogAlbumPayload, Date)] = [:]
        var incomingSnapshots: [String: ListeningArtistCatalogPayload] = [:]

        for payload in payloads {
            incomingSnapshots[payload.artistID] = payload
            for song in payload.songs {
                incomingSongs[song.songID] = (song, payload.fetchedAt)
            }
            for album in payload.albums {
                incomingAlbums[album.albumID] = (album, payload.fetchedAt)
            }
        }

        for (songID, value) in incomingSongs {
            let song = value.0
            let updatedAt = value.1
            if let existing = songsByID[songID] {
                existing.update(
                    title: song.title,
                    artistName: song.artistName,
                    albumID: song.albumID,
                    albumTitle: song.albumTitle,
                    artworkURL: song.artworkURL,
                    duration: song.duration,
                    performerArtistIDs: song.performerArtistIDs,
                    performerArtistNames: song.performerArtistNames,
                    previewURL: song.previewURL,
                    updatedAt: updatedAt
                )
            } else {
                let created = CatalogSong(
                    appleMusicSongID: song.songID,
                    title: song.title,
                    artistName: song.artistName,
                    albumID: song.albumID,
                    albumTitle: song.albumTitle,
                    artworkURL: song.artworkURL,
                    duration: song.duration,
                    performerArtistIDs: song.performerArtistIDs,
                    performerArtistNames: song.performerArtistNames,
                    previewURL: song.previewURL,
                    updatedAt: updatedAt
                )
                modelContext.insert(created)
                songsByID[songID] = created
            }
        }

        for (albumID, value) in incomingAlbums {
            let album = value.0
            let updatedAt = value.1
            if let existing = albumsByID[albumID] {
                existing.update(
                    title: album.title,
                    artworkURL: album.artworkURL,
                    releaseDate: album.releaseDate,
                    artistIDs: album.artistIDs,
                    artistNames: album.artistNames,
                    editorialText: album.editorialText,
                    genreNames: album.genreNames,
                    copyright: album.copyright,
                    recordLabelName: album.recordLabelName,
                    contentRatingRawValue: album.contentRatingRawValue,
                    audioVariantRawValues: album.audioVariantRawValues,
                    isAppleDigitalMaster: album.isAppleDigitalMaster,
                    isCompilation: album.isCompilation,
                    isSingle: album.isSingle,
                    appleMusicURL: album.appleMusicURL,
                    orderedTrackIDs: album.orderedTrackIDs,
                    updatedAt: updatedAt
                )
            } else {
                let created = CatalogAlbum(
                    appleMusicAlbumID: album.albumID,
                    title: album.title,
                    artworkURL: album.artworkURL,
                    releaseDate: album.releaseDate,
                    artistIDs: album.artistIDs,
                    artistNames: album.artistNames,
                    editorialText: album.editorialText,
                    genreNames: album.genreNames,
                    copyright: album.copyright,
                    recordLabelName: album.recordLabelName,
                    contentRatingRawValue: album.contentRatingRawValue,
                    audioVariantRawValues: album.audioVariantRawValues,
                    isAppleDigitalMaster: album.isAppleDigitalMaster,
                    isCompilation: album.isCompilation,
                    isSingle: album.isSingle,
                    appleMusicURL: album.appleMusicURL,
                    orderedTrackIDs: album.orderedTrackIDs,
                    updatedAt: updatedAt
                )
                modelContext.insert(created)
                albumsByID[albumID] = created
            }
        }

        for (artistID, payload) in incomingSnapshots {
            if let existing = snapshotsByID[artistID] {
                let cachedBrowseData = existing.featuredPlaylists
                existing.update(
                    artistName: payload.artistName,
                    artworkURL: payload.artworkURL,
                    editorialText: payload.editorialText,
                    genreNames: payload.genreNames,
                    orderedSongIDs: payload.orderedSongIDs,
                    topSongIDs: payload.topSongIDs,
                    albumIDs: payload.albumIDs,
                    featuredPlaylists: cachedBrowseData,
                    fetchedAt: payload.fetchedAt
                )
            } else {
                let created = ArtistCatalogSnapshot(
                    artistID: payload.artistID,
                    artistName: payload.artistName,
                    artworkURL: payload.artworkURL,
                    editorialText: payload.editorialText,
                    genreNames: payload.genreNames,
                    orderedSongIDs: payload.orderedSongIDs,
                    topSongIDs: payload.topSongIDs,
                    albumIDs: payload.albumIDs,
                    featuredPlaylists: [],
                    fetchedAt: payload.fetchedAt
                )
                modelContext.insert(created)
                snapshotsByID[artistID] = created
            }
        }

        try modelContext.save()
        return Set(incomingSnapshots.keys)
    }

    static func persistFeaturedPlaylists(
        _ payload: ListeningFeaturedPlaylistsPayload,
        in modelContext: ModelContext
    ) throws -> Bool {
        let artistID = payload.artistID
        let existingSnapshots = try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>(
            predicate: #Predicate { $0.artistID == artistID }))
        guard let snapshot = existingSnapshots.first else {
            return false
        }

        let songIDs = payload.songs.map(\.songID)
        let existingSongs = try modelContext.fetch(FetchDescriptor<CatalogSong>(
            predicate: #Predicate { songIDs.contains($0.appleMusicSongID) }))
        var songsByID = Dictionary(
            existingSongs.map { ($0.appleMusicSongID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Browse-only payloads may contain guest tracks. Insert tracks that core
        // enrichment does not already own, but never overwrite richer core metadata.
        for song in payload.songs where songsByID[song.songID] == nil {
            let created = CatalogSong(
                appleMusicSongID: song.songID,
                title: song.title,
                artistName: song.artistName,
                albumID: song.albumID,
                albumTitle: song.albumTitle,
                artworkURL: song.artworkURL,
                duration: song.duration,
                performerArtistIDs: song.performerArtistIDs,
                performerArtistNames: song.performerArtistNames,
                previewURL: song.previewURL,
                updatedAt: payload.fetchedAt
            )
            modelContext.insert(created)
            songsByID[song.songID] = created
        }

        snapshot.updateFeaturedPlaylists(payload.playlists)
        try modelContext.save()
        return true
    }
}
