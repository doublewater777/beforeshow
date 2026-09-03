import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningDeletionTests: XCTestCase {
    func testShowDeletionRemovesScopedListeningRowsAndKeepsGlobalRows() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date(timeIntervalSinceNow: 86_400)
        let show = try Show(name: "删除目标", date: start, startTime: start)
        let selection = CurrentShowSelection(selectedShowID: show.id)
        context.insert(show)
        context.insert(selection)
        context.insert(ShowWantsLiveSong(showID: show.id, songID: "song"))
        context.insert(ShowArtistListeningPreference(showID: show.id, artistID: "artist", isExcluded: true))
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: show.id,
            effectiveStartAtCapture: start,
            familiarSongIDsAtCapture: ["song"]
        ))
        context.insert(ShowOpeningArtistTier(
            showID: show.id,
            artistID: "artist",
            artistNameAtCapture: "Artist",
            tierRawValue: "familiar",
            baselineCapturedAt: start,
            catalogSnapshotFetchedAt: start
        ))
        context.insert(ShowSetlistMemory(showID: show.id, catalogSongID: "song"))
        context.insert(SongFamiliarityRecord(songID: "song", manualConfirmedAt: start))
        context.insert(CatalogSong(appleMusicSongID: "song", title: "Song", artistName: "Artist"))
        context.insert(CatalogAlbum(appleMusicAlbumID: "album", title: "Album"))
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist"))
        try context.save()

        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in true },
            syncWidget: { _, _ in true }
        )
        _ = try await ShowDeletionCoordinator.delete(
            show,
            from: [show],
            selections: [selection],
            notificationStates: [],
            in: context,
            effects: effects
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowSetlistMemory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogAlbum>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 1)
    }

    func testListeningLocalDataCleanerDeletesEveryListeningModel() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let showID = UUID()
        let now = Date()
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist"))
        context.insert(CatalogSong(appleMusicSongID: "song", title: "Song", artistName: "Artist"))
        context.insert(CatalogAlbum(appleMusicAlbumID: "album", title: "Album"))
        context.insert(SongFamiliarityRecord(songID: "song", actualListeningAt: now))
        context.insert(ShowWantsLiveSong(showID: showID, songID: "song"))
        context.insert(ShowArtistListeningPreference(showID: showID, artistID: "artist", isExcluded: true))
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: showID,
            effectiveStartAtCapture: now,
            familiarSongIDsAtCapture: ["song"]
        ))
        context.insert(ShowOpeningArtistTier(
            showID: showID,
            artistID: "artist",
            artistNameAtCapture: "Artist",
            tierRawValue: "deepListener",
            baselineCapturedAt: now,
            catalogSnapshotFetchedAt: now
        ))
        context.insert(ShowSetlistMemory(showID: showID, catalogSongID: "song"))
        try context.save()

        try ListeningLocalDataCleaner.deleteAll(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogAlbum>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowSetlistMemory>()), 0)
    }

    func testLocalDataInventoryIsNotEmptyWhenOnlyListeningDataExists() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SongFamiliarityRecord(songID: "song", manualConfirmedAt: Date()))
        try context.save()

        let inventory = await LocalDataInventoryService.compute(modelContext: context)

        XCTAssertFalse(inventory.isEmpty)
        XCTAssertEqual(inventory.familiarSongCount, 1)
        XCTAssertEqual(inventory.listeningRecordCount, 1)
    }
}
