import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ArtistWarmupModelTests: XCTestCase {
    func testWarmupModelsPersistExpectedLocalState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let heardAt = Date(timeIntervalSince1970: 1_783_551_600)
        let openedAt = Date(timeIntervalSince1970: 1_783_468_800)

        let artist = ShowArtist(
            showID: showID,
            originalArtistLabel: "The Chairs",
            originalOrder: 0,
            interest: .wanted
        )
        let song = CatalogSong(
            appleMusicSongID: "am-song-1",
            title: "A Slow Night",
            albumTitle: "Room Service",
            artworkURL: "https://example.com/song.jpg",
            duration: 241,
            performingArtistIDs: ["am-artist-1", "am-artist-2"],
            performingArtistNames: ["The Chairs", "Guest Singer"],
            category: .collaboration
        )
        let familiarity = SongFamiliarityRecord(
            songID: "am-song-1",
            heardAt: heardAt,
            source: .manual
        )
        let impression = ShowSongImpression(
            showID: showID,
            songID: "am-song-1",
            wantsLive: true,
            hasFeeling: true,
            note: "想在安可听",
            updatedAt: heardAt
        )
        let snapshot = ShowArtistFamiliaritySnapshot.capture(
            showID: showID,
            artistID: "am-artist-1",
            heardSongCount: 3,
            totalSongCount: 12,
            tier: .newListener,
            capturedAt: openedAt
        )
        let memory = ShowSetlistMemory(
            showID: showID,
            catalogSongID: nil,
            manualTitle: "Unreleased Encore",
            manualArtistName: "The Chairs",
            heardAtShow: heardAt,
            isMostSurprising: true
        )

        context.insert(artist)
        context.insert(song)
        context.insert(familiarity)
        context.insert(impression)
        context.insert(snapshot)
        context.insert(memory)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ShowArtist>()).first?.interest, .wanted)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CatalogSong>()).first?.category, .collaboration)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).first?.source, .manual)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShowSongImpression>()).first?.note, "想在安可听")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>()).first?.tier, .newListener)
        let storedMemory = try XCTUnwrap(context.fetch(FetchDescriptor<ShowSetlistMemory>()).first)
        XCTAssertNil(storedMemory.catalogSongID)
        XCTAssertEqual(storedMemory.manualTitle, "Unreleased Encore")
        XCTAssertTrue(storedMemory.isMostSurprising)
    }

    func testArtistMatchIsConnectedOnlyAfterUserConfirmation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let artist = ShowArtist(
            showID: UUID(),
            originalArtistLabel: "Deca Joins",
            originalOrder: 1,
            interest: .maybe
        )

        XCTAssertEqual(artist.connectionState, .notConnected)
        XCTAssertFalse(artist.isConnectedToAppleMusic)
        XCTAssertNil(artist.appleMusicArtistID)

        artist.confirmAppleMusicArtist(
            id: "am-artist-9",
            name: "deca joins",
            artworkURL: "https://example.com/artist.jpg",
            confirmedAt: Date(timeIntervalSince1970: 1_783_468_800)
        )
        context.insert(artist)
        try context.save()

        let storedArtist = try XCTUnwrap(context.fetch(FetchDescriptor<ShowArtist>()).first)
        XCTAssertEqual(storedArtist.connectionState, .connected)
        XCTAssertTrue(storedArtist.isConnectedToAppleMusic)
        XCTAssertEqual(storedArtist.appleMusicArtistID, "am-artist-9")
        XCTAssertEqual(storedArtist.appleMusicArtistName, "deca joins")
        XCTAssertEqual(storedArtist.appleMusicArtworkURL, "https://example.com/artist.jpg")
    }

    func testIncompleteCatalogSnapshotDoesNotPresentDenominator() throws {
        let loading = ArtistCatalogSnapshot.loading(artistID: "am-artist-1")
        let failed = ArtistCatalogSnapshot.failed(
            artistID: "am-artist-2",
            fetchedAt: Date(timeIntervalSince1970: 1_783_468_800)
        )
        let complete = ArtistCatalogSnapshot.complete(
            artistID: "am-artist-3",
            songIDs: ["song-a", "song-a", "song-b"],
            fetchedAt: Date(timeIntervalSince1970: 1_783_468_900)
        )

        XCTAssertEqual(loading.state, .loading)
        XCTAssertNil(loading.denominatorSongCount)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNil(failed.denominatorSongCount)
        XCTAssertEqual(complete.state, .complete)
        XCTAssertEqual(complete.uniqueSongIDs, ["song-a", "song-b"])
        XCTAssertEqual(complete.denominatorSongCount, 2)
    }

    func testShowSongImpressionUpsertReplacesExistingRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = ArtistWarmupRepository(context: context)
        let showID = UUID()

        _ = try repository.upsertImpression(
            showID: showID,
            songID: "am-song-1",
            wantsLive: true,
            hasFeeling: false,
            note: nil,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try repository.upsertImpression(
            showID: showID,
            songID: "am-song-1",
            wantsLive: false,
            hasFeeling: true,
            note: "后来更喜欢",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ShowSongImpression>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].showID, showID)
        XCTAssertEqual(stored[0].songID, "am-song-1")
        XCTAssertFalse(stored[0].wantsLive)
        XCTAssertTrue(stored[0].hasFeeling)
        XCTAssertEqual(stored[0].note, "后来更喜欢")
        XCTAssertEqual(stored[0].updatedAt, Date(timeIntervalSince1970: 200))
    }

    func testDeletingShowLocalRecordDoesNotDeleteGlobalSongFamiliarity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        let songID = "am-song-1"
        let familiarity = SongFamiliarityRecord(
            songID: songID,
            heardAt: Date(timeIntervalSince1970: 1_783_551_600),
            source: .showRecall
        )
        let impression = ShowSongImpression(
            showID: showID,
            songID: songID,
            wantsLive: true,
            hasFeeling: true,
            note: nil,
            updatedAt: Date(timeIntervalSince1970: 1_783_551_700)
        )
        context.insert(familiarity)
        context.insert(impression)
        try context.save()

        context.delete(impression)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowSongImpression>()).isEmpty)
        let storedFamiliarity = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(storedFamiliarity.count, 1)
        XCTAssertEqual(storedFamiliarity[0].songID, songID)
        XCTAssertEqual(storedFamiliarity[0].source, .showRecall)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ShowArtist.self,
            ArtistCatalogSnapshot.self,
            CatalogSong.self,
            SongFamiliarityRecord.self,
            ShowSongImpression.self,
            ShowArtistFamiliaritySnapshot.self,
            ShowSetlistMemory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
