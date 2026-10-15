import Foundation
import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningArtistMatchingTests: XCTestCase {
    func testCandidateDoesNotWriteUntilConfirmation() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let candidate = RecognizedArtist(id: "new", canonicalName: "New Artist", avatarURL: nil, appleMusicURL: URL(string: "https://music.apple.com/artist/123"))
        XCTAssertNil(show.artists[1].appleMusicArtistID)
        await room.rematch(slotIndex: 1, artist: candidate)
        XCTAssertEqual(show.artists[1].appleMusicArtistID, "new")
        XCTAssertEqual(show.artists[1].name, "New Artist")
        XCTAssertEqual(show.artists[1].appleMusicURL, candidate.appleMusicURL?.absoluteString)
        XCTAssertEqual(room.browser.scope, .artist("new"))
        XCTAssertEqual(room.browsingArtist?.name, "New Artist")
    }
}
@MainActor final class ListeningArtistPreferenceTests: XCTestCase {
    func testScopeIsRuntimeAndExclusionReturnsToWholeShow() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.filterArtist("a")
        XCTAssertEqual(room.onlyArtistID, "a")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        room.excludeArtist("a", excluded: true)
        XCTAssertNil(room.onlyArtistID)
        XCTAssertEqual(room.excludedArtistIDs, ["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<ShowArtistListeningPreference>())
        XCTAssertTrue(rows.allSatisfy { $0.showID == show.id })
        room.excludeArtist("a", excluded: false)
        XCTAssertTrue(room.excludedArtistIDs.isEmpty)
    }
}
@MainActor final class ListeningArtistLibraryTests: XCTestCase {
    func testTopAndAlbumOrderUseCatalogAndUnconnectedDoesNotBlock() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertEqual(room.discs.first?.tracks.map(\.id), ["a2"])
        let artist = try XCTUnwrap(room.artistPresentation("a"))
        XCTAssertEqual(artist.top.map(\.id), ["a2"])
        XCTAssertEqual(artist.albums.first?.tracks.map(\.id), ["a2", "a1"])
        XCTAssertTrue(try XCTUnwrap(room.artistPresentation("c")).top.isEmpty)
        room.playLibrarySong(artist.all[1], artistID: "a")
        try await ListenTestData.settle(room) { room.isPlaying && room.track?.id == "a2" }
        XCTAssertEqual(room.mechanism.disc?.id, "album")
        room.setActive(false)
    }
}
@MainActor final class ListeningArtistRematchTests: XCTestCase {
    func testRematchKeepsBaselineAndGlobalEvidence() async throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        let repo = ListeningRepository(modelContext: context)
        try repo.confirmManualFamiliarity(songID: "a1", at: Date().addingTimeInterval(-20000))
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
        try repo.setArtistExcluded(showID: show.id, artistID: "a", isExcluded: true)
        try context.save()
        let baseline = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()).first)
        let captured = baseline.capturedAt
        let room = ListenTestData.room(context)
        await room.load(show: show)
        await room.rematch(slotIndex: 0, artist: .init(id: "replacement", canonicalName: "Replacement", avatarURL: nil, appleMusicURL: nil))
        XCTAssertEqual(baseline.capturedAt, captured)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>()).contains { $0.artistID == "a" })
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).contains { $0.artistID == "a" })
    }
}
