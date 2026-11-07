import XCTest
@testable import BeforeShow

@MainActor
final class ListeningPickAuditionTests: XCTestCase {
    func testAuditionPlaysOnlyPreviewableTracksInTheRecordsOwnOrder() {
        let tracks = [
            ListeningDiscTrack(CatalogSong(appleMusicSongID: "1", title: "A", artistName: "X", previewURL: "https://p/1.m4a")),
            ListeningDiscTrack(CatalogSong(appleMusicSongID: "2", title: "B", artistName: "X")),
            ListeningDiscTrack(CatalogSong(appleMusicSongID: "3", title: "C", artistName: "X", previewURL: "https://p/3.m4a"))
        ]
        let disc = ListeningDisc(id: "d", title: "D", artworkURL: nil, tracks: tracks)
        XCTAssertEqual(ListeningPickAudition.items(for: disc).map(\.songID), ["1", "3"])
    }

    func testAuditioningLeavesTheDeckAndMiniPlayerAlone() async throws {
        let (container, show) = try ListenTestData.make()
        _ = container
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .multiFull),
            artistSearchService: PickAuditionArtistSearch(),
            playbackFactory: { _ in player }
        )
        defer { room.stop() }
        await room.load(show: show)
        let songs = (room.compilationDiscs + room.browseArtists.flatMap(\.albums)).flatMap(\.tracks)
        try XCTSkipIf(songs.count < 2)
        let playing = ListeningDisc(id: "playing", title: "P", artworkURL: nil, tracks: [songs[0]])
        let browsed = ListeningDisc(id: "browsed", title: "B", artworkURL: nil, tracks: [songs[1]])
        room.loadDisc(playing)
        try await ListenTestData.settle(room, until: { room.isPlaying })

        let audition = ListeningPickAudition()
        audition.play(browsed)
        XCTAssertEqual(room.loadedDisc?.id, "playing")
        audition.stop(resumeListening: true)
        XCTAssertEqual(room.loadedDisc?.id, "playing")
    }
}

private struct PickAuditionArtistSearch: ArtistSearchServicing {
    func searchArtists(query: String) async throws -> [RecognizedArtist] { [] }
}
