import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningPersistenceTests: XCTestCase {
    func testModelContainerFactoryRegistersAllListeningModels() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let showID = UUID()
        context.insert(ArtistCatalogSnapshot(artistID: "1", artistName: "A"))
        context.insert(CatalogSong(appleMusicSongID: "10", title: "Song", artistName: "A"))
        context.insert(CatalogAlbum(appleMusicAlbumID: "20", title: "Album"))
        context.insert(SongFamiliarityRecord(songID: "10", manualConfirmedAt: Date()))
        context.insert(ShowWantsLiveSong(showID: showID, songID: "10"))
        context.insert(ShowArtistListeningPreference(showID: showID, artistID: "1", isExcluded: true))
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: showID,
            effectiveStartAtCapture: Date(),
            familiarSongIDsAtCapture: ["10"]
        ))
        context.insert(ShowOpeningArtistTier(
            showID: showID,
            artistID: "1",
            artistNameAtCapture: "A",
            tierRawValue: "familiar",
            baselineCapturedAt: Date(),
            catalogSnapshotFetchedAt: Date()
        ))
        context.insert(ShowSetlistMemory(showID: showID, catalogSongID: "10"))
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogAlbum>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowSetlistMemory>()), 1)
    }

    func testUniqueWritesFetchThenMutateInsteadOfBlindInsert() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let repository = ListeningRepository(modelContext: context)
        let showID = UUID()
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        _ = try repository.upsertArtistCatalogSnapshot(
            artistID: "1", artistName: "Old", artworkURL: nil, editorialText: nil,
            genreNames: ["Rock"], orderedSongIDs: ["10"], topSongIDs: ["10"], albumIDs: ["20"],
            fetchedAt: firstDate
        )
        _ = try repository.upsertArtistCatalogSnapshot(
            artistID: "1", artistName: "New", artworkURL: "art", editorialText: "bio",
            genreNames: ["Pop"], orderedSongIDs: ["11", "10"], topSongIDs: ["11"], albumIDs: ["21"],
            fetchedAt: secondDate
        )
        _ = try repository.upsertCatalogSong(songID: "10", title: "Old", artistName: "A")
        _ = try repository.upsertCatalogSong(
            songID: "10", title: "New", artistName: "A", performerArtistIDs: ["1", "2"],
            performerArtistNames: ["A", "B"], updatedAt: secondDate
        )
        _ = try repository.upsertCatalogAlbum(albumID: "20", title: "Old", orderedTrackIDs: ["10"])
        _ = try repository.upsertCatalogAlbum(
            albumID: "20", title: "New", artistIDs: ["1"], orderedTrackIDs: ["11", "10"], updatedAt: secondDate
        )
        try repository.setWantsLive(showID: showID, songID: "10", isWanted: true)
        try repository.setWantsLive(showID: showID, songID: "10", isWanted: true)
        try repository.setArtistExcluded(showID: showID, artistID: "1", isExcluded: true)
        try repository.setArtistExcluded(showID: showID, artistID: "1", isExcluded: true, at: secondDate)
        _ = try repository.insertOpeningBaselineIfAbsent(
            showID: showID, effectiveStart: firstDate, familiarSongIDs: ["10"], capturedAt: firstDate
        )
        _ = try repository.insertOpeningBaselineIfAbsent(
            showID: showID, effectiveStart: secondDate, familiarSongIDs: ["11"], capturedAt: secondDate
        )
        _ = try repository.insertOpeningTierIfAbsent(
            showID: showID, artistID: "1", artistName: "A", tierRawValue: "newListener",
            baselineCapturedAt: firstDate, catalogSnapshotFetchedAt: firstDate, resolvedAt: firstDate
        )
        _ = try repository.insertOpeningTierIfAbsent(
            showID: showID, artistID: "1", artistName: "A", tierRawValue: "deepListener",
            baselineCapturedAt: secondDate, catalogSnapshotFetchedAt: secondDate, resolvedAt: secondDate
        )
        _ = try repository.confirmManualFamiliarity(songID: "10", at: firstDate)
        _ = try repository.confirmActualFamiliarity(songID: "10", at: secondDate)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogAlbum>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)

        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<ArtistCatalogSnapshot>()).first)
        XCTAssertEqual(snapshot.artistName, "New")
        XCTAssertEqual(snapshot.orderedSongIDs, ["11", "10"])
        let song = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogSong>()).first)
        XCTAssertEqual(song.title, "New")
        XCTAssertEqual(song.performerArtistIDs, ["1", "2"])
        let baseline = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()).first)
        XCTAssertEqual(baseline.familiarSongIDsAtCapture, ["10"], "opening baseline is immutable once captured")
        let tier = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).first)
        XCTAssertEqual(tier.tierRawValue, "newListener", "opening tier is immutable once resolved")
        let familiarity = try XCTUnwrap(context.fetch(FetchDescriptor<SongFamiliarityRecord>()).first)
        XCTAssertEqual(familiarity.manualConfirmedAt, firstDate)
        XCTAssertEqual(familiarity.actualListeningAt, secondDate)
    }

    func testArtistIdentityMigrationCopiesArrayAndIsIdempotent() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try Show(
            name: "Identity",
            date: Date(),
            startTime: Date(),
            artists: [ArtistSlot(
                name: "Artist",
                avatarURL: nil,
                appleMusicURL: "https://music.apple.com/cn/artist/artist-name/123456789"
            )]
        )
        context.insert(show)
        try context.save()

        AppleMusicArtistIdentityMigration.migrateIfNeeded(in: context)
        AppleMusicArtistIdentityMigration.migrateIfNeeded(in: context)

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(stored.artists.first?.appleMusicArtistID, "123456789")
        XCTAssertEqual(stored.artists.count, 1)
        XCTAssertNil(AppleMusicArtistIdentityMigration.artistID(from: "https://example.com/artist/123"))
        XCTAssertNil(AppleMusicArtistIdentityMigration.artistID(from: "https://music.apple.com/cn/artist/name/not-a-number"))
    }

    func testEditingArtistNameClearsCatalogIdentity() throws {
        let now = Date()
        let show = try Show(
            name: "Edit",
            date: now,
            startTime: now,
            artists: [ArtistSlot(
                name: "Old",
                avatarURL: "avatar",
                appleMusicURL: "https://music.apple.com/cn/artist/old/123",
                appleMusicArtistID: "123",
                albumArtworkURL: "album"
            )]
        )
        var draft = ShowDraft(
            name: "Edit",
            date: now,
            startTime: now,
            artists: [ArtistSlot(
                name: "New",
                avatarURL: "avatar",
                appleMusicURL: "https://music.apple.com/cn/artist/old/123",
                appleMusicArtistID: "123",
                albumArtworkURL: "album"
            )]
        )
        draft.artists[0].name = "New"

        try show.apply(draft)

        XCTAssertNil(show.artists[0].avatarURL)
        XCTAssertNil(show.artists[0].appleMusicURL)
        XCTAssertNil(show.artists[0].appleMusicArtistID)
        XCTAssertNil(show.artists[0].albumArtworkURL)
    }

    func testFamiliarityResolverKeepsIndependentEvidence() {
        let manual = SongFamiliarityRecord(
            songID: "manual",
            manualConfirmedAt: Date(timeIntervalSince1970: 10)
        )
        let actual = SongFamiliarityRecord(
            songID: "actual",
            actualListeningAt: Date(timeIntervalSince1970: 20)
        )
        let recall = ShowSetlistMemory(
            showID: UUID(),
            catalogSongID: "recall",
            createdAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "manual", records: [manual, actual], setlistMemories: [recall]
        ))
        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "actual", records: [manual, actual], setlistMemories: [recall]
        ))
        XCTAssertTrue(FamiliarityEvidenceResolver.isFamiliar(
            songID: "recall", records: [manual, actual], setlistMemories: [recall]
        ))
        XCTAssertEqual(
            FamiliarityEvidenceResolver.familiarSongIDs(records: [manual, actual], setlistMemories: [recall]),
            Set(["manual", "actual", "recall"])
        )
    }
}
