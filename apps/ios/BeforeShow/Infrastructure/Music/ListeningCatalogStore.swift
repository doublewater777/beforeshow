import Foundation
import SwiftData

@MainActor
final class ListeningCatalogStore {
    private let modelContext: ModelContext
    private let service: any ListeningMusicCatalogServicing
    private var revalidationTasks: [String: Task<Void, Never>] = [:]

    init(
        modelContext: ModelContext,
        service: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService()
    ) {
        self.modelContext = modelContext
        self.service = service
    }

    func cachedSnapshot(artistID: String) throws -> ArtistCatalogSnapshot? {
        try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
            .first(where: { $0.artistID == artistID })
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
        // MusicKit builds the complete in-memory payload before this persistence
        // transaction begins. A failed/partial network refresh therefore never
        // replaces the last-good ArtistCatalogSnapshot denominator.
        let payload = try await service.fetchArtistCatalog(
            artistID: artistID,
            fetchedAt: now
        )
        let repository = ListeningRepository(modelContext: modelContext)

        do {
            for song in payload.songs {
                try repository.upsertCatalogSong(
                    songID: song.songID,
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
            }
            for album in payload.albums {
                try repository.upsertCatalogAlbum(
                    albumID: album.albumID,
                    title: album.title,
                    artworkURL: album.artworkURL,
                    releaseDate: album.releaseDate,
                    artistIDs: album.artistIDs,
                    orderedTrackIDs: album.orderedTrackIDs,
                    updatedAt: payload.fetchedAt
                )
            }
            let snapshot = try repository.upsertArtistCatalogSnapshot(
                artistID: payload.artistID,
                artistName: payload.artistName,
                artworkURL: payload.artworkURL,
                editorialText: payload.editorialText,
                genreNames: payload.genreNames,
                orderedSongIDs: payload.orderedSongIDs,
                topSongIDs: payload.topSongIDs,
                albumIDs: payload.albumIDs,
                fetchedAt: payload.fetchedAt
            )
            try modelContext.save()
            return snapshot
        } catch {
            modelContext.rollback()
            throw error
        }
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
