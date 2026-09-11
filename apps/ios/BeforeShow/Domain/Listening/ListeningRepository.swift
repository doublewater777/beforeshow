import Foundation
import SwiftData

@MainActor
struct ListeningRepository {
    let modelContext: ModelContext

    @discardableResult
    func upsertArtistCatalogSnapshot(
        artistID: String,
        artistName: String,
        artworkURL: String?,
        editorialText: String?,
        genreNames: [String],
        orderedSongIDs: [String],
        topSongIDs: [String],
        albumIDs: [String],
        fetchedAt: Date
    ) throws -> ArtistCatalogSnapshot {
        let snapshots = try modelContext.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
        if let existing = snapshots.first(where: { $0.artistID == artistID }) {
            existing.update(
                artistName: artistName,
                artworkURL: artworkURL,
                editorialText: editorialText,
                genreNames: genreNames,
                orderedSongIDs: orderedSongIDs,
                topSongIDs: topSongIDs,
                albumIDs: albumIDs,
                fetchedAt: fetchedAt
            )
            return existing
        }
        let created = ArtistCatalogSnapshot(
            artistID: artistID,
            artistName: artistName,
            artworkURL: artworkURL,
            editorialText: editorialText,
            genreNames: genreNames,
            orderedSongIDs: orderedSongIDs,
            topSongIDs: topSongIDs,
            albumIDs: albumIDs,
            fetchedAt: fetchedAt
        )
        modelContext.insert(created)
        return created
    }

    @discardableResult
    func upsertCatalogSong(
        songID: String,
        title: String,
        artistName: String,
        albumID: String? = nil,
        albumTitle: String? = nil,
        artworkURL: String? = nil,
        duration: TimeInterval? = nil,
        performerArtistIDs: [String] = [],
        performerArtistNames: [String] = [],
        previewURL: String? = nil,
        updatedAt: Date = Date()
    ) throws -> CatalogSong {
        let songs = try modelContext.fetch(FetchDescriptor<CatalogSong>())
        if let existing = songs.first(where: { $0.appleMusicSongID == songID }) {
            existing.update(
                title: title,
                artistName: artistName,
                albumID: albumID,
                albumTitle: albumTitle,
                artworkURL: artworkURL,
                duration: duration,
                performerArtistIDs: performerArtistIDs,
                performerArtistNames: performerArtistNames,
                previewURL: previewURL,
                updatedAt: updatedAt
            )
            return existing
        }
        let created = CatalogSong(
            appleMusicSongID: songID,
            title: title,
            artistName: artistName,
            albumID: albumID,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            duration: duration,
            performerArtistIDs: performerArtistIDs,
            performerArtistNames: performerArtistNames,
            previewURL: previewURL,
            updatedAt: updatedAt
        )
        modelContext.insert(created)
        return created
    }

    @discardableResult
    func upsertCatalogAlbum(
        albumID: String,
        title: String,
        artworkURL: String? = nil,
        releaseDate: Date? = nil,
        artistIDs: [String] = [],
        artistNames: [String] = [],
        editorialText: String? = nil,
        genreNames: [String] = [],
        copyright: String? = nil,
        recordLabelName: String? = nil,
        contentRatingRawValue: String? = nil,
        audioVariantRawValues: [String] = [],
        isAppleDigitalMaster: Bool? = nil,
        isCompilation: Bool? = nil,
        isSingle: Bool? = nil,
        appleMusicURL: String? = nil,
        orderedTrackIDs: [String] = [],
        updatedAt: Date = Date()
    ) throws -> CatalogAlbum {
        let albums = try modelContext.fetch(FetchDescriptor<CatalogAlbum>())
        if let existing = albums.first(where: { $0.appleMusicAlbumID == albumID }) {
            existing.update(
                title: title,
                artworkURL: artworkURL,
                releaseDate: releaseDate,
                artistIDs: artistIDs,
                artistNames: artistNames,
                editorialText: editorialText,
                genreNames: genreNames,
                copyright: copyright,
                recordLabelName: recordLabelName,
                contentRatingRawValue: contentRatingRawValue,
                audioVariantRawValues: audioVariantRawValues,
                isAppleDigitalMaster: isAppleDigitalMaster,
                isCompilation: isCompilation,
                isSingle: isSingle,
                appleMusicURL: appleMusicURL,
                orderedTrackIDs: orderedTrackIDs,
                updatedAt: updatedAt
            )
            return existing
        }
        let created = CatalogAlbum(
            appleMusicAlbumID: albumID,
            title: title,
            artworkURL: artworkURL,
            releaseDate: releaseDate,
            artistIDs: artistIDs,
            artistNames: artistNames,
            editorialText: editorialText,
            genreNames: genreNames,
            copyright: copyright,
            recordLabelName: recordLabelName,
            contentRatingRawValue: contentRatingRawValue,
            audioVariantRawValues: audioVariantRawValues,
            isAppleDigitalMaster: isAppleDigitalMaster,
            isCompilation: isCompilation,
            isSingle: isSingle,
            appleMusicURL: appleMusicURL,
            orderedTrackIDs: orderedTrackIDs,
            updatedAt: updatedAt
        )
        modelContext.insert(created)
        return created
    }

    @discardableResult
    func confirmManualFamiliarity(songID: String, at date: Date = Date()) throws -> SongFamiliarityRecord {
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: modelContext, now: date)
        let records = try modelContext.fetch(FetchDescriptor<SongFamiliarityRecord>())
        if let existing = records.first(where: { $0.songID == songID }) {
            existing.confirmManual(at: date)
            return existing
        }
        let created = SongFamiliarityRecord(songID: songID, manualConfirmedAt: date, updatedAt: date)
        modelContext.insert(created)
        return created
    }

    @discardableResult
    func confirmActualFamiliarity(songID: String, at date: Date = Date()) throws -> SongFamiliarityRecord {
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: modelContext, now: date)
        let records = try modelContext.fetch(FetchDescriptor<SongFamiliarityRecord>())
        if let existing = records.first(where: { $0.songID == songID }) {
            existing.confirmActualListening(at: date)
            return existing
        }
        let created = SongFamiliarityRecord(songID: songID, actualListeningAt: date, updatedAt: date)
        modelContext.insert(created)
        return created
    }

    func undoManualFamiliarity(songID: String, at date: Date = Date()) throws {
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: modelContext, now: date)
        let records = try modelContext.fetch(FetchDescriptor<SongFamiliarityRecord>())
        guard let existing = records.first(where: { $0.songID == songID }) else { return }
        existing.clearManual(at: date)
        if existing.actualListeningAt == nil {
            modelContext.delete(existing)
        }
    }

    @discardableResult
    func addSetlistMemory(
        showID: UUID,
        catalogSongID: String? = nil,
        manualTitle: String? = nil,
        manualArtistName: String? = nil,
        mostSurprising: Bool = false,
        at date: Date = Date()
    ) throws -> ShowSetlistMemory {
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: modelContext, now: date)
        let memory = ShowSetlistMemory(
            showID: showID,
            catalogSongID: catalogSongID,
            manualTitle: manualTitle,
            manualArtistName: manualArtistName,
            isMostSurprising: mostSurprising,
            createdAt: date,
            updatedAt: date
        )
        modelContext.insert(memory)
        return memory
    }

    func deleteSetlistMemory(_ memory: ShowSetlistMemory, at date: Date = Date()) throws {
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: modelContext, now: date)
        modelContext.delete(memory)
    }

    func setWantsLive(showID: UUID, songID: String, isWanted: Bool, at date: Date = Date()) throws {
        if let show = try modelContext.fetch(FetchDescriptor<Show>()).first(where: { $0.id == showID }),
           !WantsLivePolicy.isMutable(show: show, now: date) {
            throw ListeningMutationError.wantsLiveFrozen(showID)
        }

        let key = ShowWantsLiveSong.makeUniqueKey(showID: showID, songID: songID)
        let rows = try modelContext.fetch(FetchDescriptor<ShowWantsLiveSong>())
        let existing = rows.first(where: { $0.uniqueKey == key })
        if isWanted {
            if existing == nil {
                modelContext.insert(ShowWantsLiveSong(showID: showID, songID: songID, createdAt: date))
            }
        } else if let existing {
            modelContext.delete(existing)
        }
    }

    func setArtistExcluded(showID: UUID, artistID: String, isExcluded: Bool, at date: Date = Date()) throws {
        let key = ShowArtistListeningPreference.makeUniqueKey(showID: showID, artistID: artistID)
        let rows = try modelContext.fetch(FetchDescriptor<ShowArtistListeningPreference>())
        let existing = rows.first(where: { $0.uniqueKey == key })
        if isExcluded {
            if let existing {
                existing.isExcluded = true
                existing.updatedAt = date
            } else {
                modelContext.insert(ShowArtistListeningPreference(
                    showID: showID,
                    artistID: artistID,
                    isExcluded: true,
                    updatedAt: date
                ))
            }
        } else if let existing {
            modelContext.delete(existing)
        }
    }

    @discardableResult
    func insertOpeningBaselineIfAbsent(
        showID: UUID,
        effectiveStart: Date,
        familiarSongIDs: [String],
        capturedAt: Date
    ) throws -> ShowOpeningFamiliarityBaseline {
        let key = ShowOpeningFamiliarityBaseline.makeUniqueKey(showID: showID)
        let rows = try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>())
        if let existing = rows.first(where: { $0.showIDKey == key }) {
            return existing
        }
        let created = ShowOpeningFamiliarityBaseline(
            showID: showID,
            effectiveStartAtCapture: effectiveStart,
            familiarSongIDsAtCapture: familiarSongIDs,
            capturedAt: capturedAt
        )
        modelContext.insert(created)
        return created
    }

    @discardableResult
    func insertOpeningTierIfAbsent(
        showID: UUID,
        artistID: String,
        artistName: String,
        tierRawValue: String,
        baselineCapturedAt: Date,
        catalogSnapshotFetchedAt: Date,
        resolvedAt: Date
    ) throws -> ShowOpeningArtistTier {
        let key = ShowOpeningArtistTier.makeUniqueKey(showID: showID, artistID: artistID)
        let rows = try modelContext.fetch(FetchDescriptor<ShowOpeningArtistTier>())
        if let existing = rows.first(where: { $0.uniqueKey == key }) {
            return existing
        }
        let created = ShowOpeningArtistTier(
            showID: showID,
            artistID: artistID,
            artistNameAtCapture: artistName,
            tierRawValue: tierRawValue,
            baselineCapturedAt: baselineCapturedAt,
            catalogSnapshotFetchedAt: catalogSnapshotFetchedAt,
            resolvedAt: resolvedAt
        )
        modelContext.insert(created)
        return created
    }
}
