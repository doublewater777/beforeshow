import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ArtistWarmupDeletionIntegrationTests: XCTestCase {
    func testDeletingShowRemovesShowLocalWarmupRecordsAndPreservesGlobalCatalog() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let deletedStart = Date(timeIntervalSince1970: 2_000_000_000)
        let remainingStart = Date(timeIntervalSince1970: 2_000_086_400)
        let deleted = try Show(name: "删除的现场", date: deletedStart, startTime: deletedStart)
        let remaining = try Show(name: "保留的现场", date: remainingStart, startTime: remainingStart)
        let deletedID = deleted.id
        let remainingID = remaining.id
        let selection = CurrentShowSelection(selectedShowID: deletedID)
        let notificationState = NotificationSchedulingState(focusedShowID: deletedID)

        context.insert(deleted)
        context.insert(remaining)
        context.insert(selection)
        context.insert(notificationState)
        insertWarmupRecords(showID: deletedID, artistID: "artist-1", songID: "song-1", in: context)
        insertWarmupRecords(showID: remainingID, artistID: "artist-2", songID: "song-2", in: context)
        context.insert(ArtistCatalogSnapshot.complete(
            artistID: "artist-1",
            songIDs: ["song-1"],
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_100)
        ))
        context.insert(CatalogSong(
            appleMusicSongID: "song-1",
            title: "Encore",
            performingArtistIDs: ["artist-1"],
            performingArtistNames: ["Artist 1"],
            category: .album
        ))
        context.insert(SongFamiliarityRecord(
            songID: "song-1",
            heardAt: Date(timeIntervalSince1970: 2_000_000_200),
            source: .showRecall
        ))
        try context.save()

        var verifiedPostCommitState = false
        let effects = CurrentShowPostCommitEffects(
            applyNotificationFocus: { currentShow, _ in
                XCTAssertEqual(currentShow?.id, remainingID)
                do {
                    let verificationContext = ModelContext(container)
                    try self.assertDeletedShowWarmupRecordsRemoved(deletedID, in: verificationContext)
                    try self.assertRemainingShowWarmupRecordsPreserved(remainingID, in: verificationContext)
                    try self.assertGlobalWarmupRecordsPreserved(in: verificationContext)
                    verifiedPostCommitState = true
                } catch {
                    XCTFail("Failed to verify committed deletion state: \(error)")
                }
                return true
            },
            syncWidget: { shows, manualSelection in
                XCTAssertEqual(shows.map(\.id), [remainingID])
                XCTAssertNil(manualSelection?.selectedShowID)
                return true
            }
        )

        let result = try await ShowDeletionCoordinator.delete(
            deleted,
            from: [deleted, remaining],
            selections: [selection],
            notificationStates: [notificationState],
            in: context,
            effects: effects
        )

        XCTAssertEqual(result, .complete(didSync: true))
        XCTAssertTrue(verifiedPostCommitState)
        try assertDeletedShowWarmupRecordsRemoved(deletedID, in: ModelContext(container))
        try assertRemainingShowWarmupRecordsPreserved(remainingID, in: ModelContext(container))
        try assertGlobalWarmupRecordsPreserved(in: ModelContext(container))
    }

    private func insertWarmupRecords(
        showID: UUID,
        artistID: String,
        songID: String,
        in context: ModelContext
    ) {
        let artist = ShowArtist(
            showID: showID,
            originalArtistLabel: "Artist \(artistID)",
            originalOrder: 0,
            interest: .wanted
        )
        artist.confirmAppleMusicArtist(id: artistID, name: "Artist \(artistID)", artworkURL: nil)
        context.insert(artist)
        context.insert(ShowSongImpression(
            showID: showID,
            songID: songID,
            wantsLive: true,
            hasFeeling: true,
            note: nil
        ))
        context.insert(ShowArtistFamiliaritySnapshot.capture(
            showID: showID,
            artistID: artistID,
            heardSongCount: 1,
            totalSongCount: 1,
            tier: .complete
        ))
        context.insert(ShowSetlistMemory(
            showID: showID,
            catalogSongID: songID,
            manualTitle: nil,
            manualArtistName: nil,
            heardAtShow: Date(timeIntervalSince1970: 2_000_000_300)
        ))
    }

    private func assertDeletedShowWarmupRecordsRemoved(
        _ showID: UUID,
        in context: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<Show>()).contains { $0.id == showID },
            file: file,
            line: line
        )
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<ShowArtist>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<ShowSongImpression>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<ShowSetlistMemory>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
    }

    private func assertRemainingShowWarmupRecordsPreserved(
        _ showID: UUID,
        in context: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ShowArtist>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ShowSongImpression>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ShowArtistFamiliaritySnapshot>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ShowSetlistMemory>()).contains { $0.showID == showID },
            file: file,
            line: line
        )
    }

    private func assertGlobalWarmupRecordsPreserved(
        in context: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ArtistCatalogSnapshot>()).map(\.artistID),
            ["artist-1"],
            file: file,
            line: line
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CatalogSong>()).map(\.appleMusicSongID),
            ["song-1"],
            file: file,
            line: line
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).map(\.songID),
            ["song-1"],
            file: file,
            line: line
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            NotificationSchedulingState.self,
            MemoryFragment.self,
            MemoryMediaItem.self,
            ShowAsset.self,
            DynamicCover.self,
            ShowArtist.self,
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
