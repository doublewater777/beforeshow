import XCTest
@testable import BeforeShow

final class ListeningDiscShuffleTests: XCTestCase {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func disc(_ id: String, tracks: Int = 3) -> ListeningDisc {
        ListeningDisc(id: id, title: id, artworkURL: nil, tracks: (0..<tracks).map {
            ListeningDiscTrack(CatalogSong(appleMusicSongID: "\(id)-\($0)", title: "\($0)", artistName: "A"))
        })
    }

    func testEveryRecordPlaysOnceBeforeAnyRepeats() throws {
        let discs = ["a", "b", "c", "d"].map { disc($0) }
        var run = try XCTUnwrap(ListeningDiscShuffle(artistID: "x", discs: discs))
        var generator = SeededGenerator(state: 7)
        var last: ListeningDisc?
        var round: [String] = []
        for _ in discs {
            let next = run.next(after: last, using: &generator)
            round.append(next.id)
            last = next
        }
        XCTAssertEqual(Set(round), ["a", "b", "c", "d"])
    }

    func testNewRoundNeverOpensWithTheRecordThatJustEnded() throws {
        let discs = ["a", "b"].map { disc($0) }
        for seed in 0..<50 {
            var run = try XCTUnwrap(ListeningDiscShuffle(artistID: "x", discs: discs))
            var generator = SeededGenerator(state: UInt64(seed))
            var last: ListeningDisc?
            for _ in 0..<6 {
                let next = run.next(after: last, using: &generator)
                XCTAssertNotEqual(next.id, last?.id)
                last = next
            }
        }
    }

    func testRecordsKeepTheirOwnTrackOrderAndEmptyOnesAreSkipped() throws {
        let album = disc("album", tracks: 5)
        var run = try XCTUnwrap(ListeningDiscShuffle(artistID: "x", discs: [album, disc("empty", tracks: 0)]))
        let next = run.next(after: nil)
        XCTAssertEqual(next, album)
        XCTAssertNil(ListeningDiscShuffle(artistID: "x", discs: [disc("empty", tracks: 0)]))
    }
}

@MainActor
final class ListeningDiscShuffleRoomTests: XCTestCase {
    func testFinishedRecordHandsOverToAnotherWholeRecordAndManualPickEndsTheRun() async throws {
        let (container, show) = try ListenTestData.make()
        _ = container
        let player = ListeningTestPlayer()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .multiFull),
            artistSearchService: ShuffleArtistSearch(),
            playbackFactory: { _ in player }
        )
        defer { room.stop() }
        await room.load(show: show)
        let source = try XCTUnwrap(room.compilationDiscs.first)
        let songs = (room.compilationDiscs + room.browseArtists.flatMap(\.albums)).flatMap(\.tracks)
        try XCTSkipIf(songs.count < 2, "fixture needs two songs")
        let first = ListeningDisc(id: "shuffle-a", title: "A", artworkURL: nil, tracks: [songs[0]])
        let second = ListeningDisc(id: "shuffle-b", title: "B", artworkURL: nil, tracks: [songs[1]])

        room.shuffleDiscography(of: "artist", discs: [first, second])
        try await ListenTestData.settle(room, until: { room.isPlaying })
        let opening = try XCTUnwrap(room.loadedDisc)
        XCTAssertEqual(player.loadedSongIDs, opening.tracks.map(\.id))

        player.hasEnded = true
        player.phase = .stopped
        try await ListenTestData.settle(room, until: { room.loadedDisc != opening && room.isPlaying })
        let following = try XCTUnwrap(room.loadedDisc)
        XCTAssertNotEqual(following.id, opening.id)
        XCTAssertEqual(player.loadedSongIDs, following.tracks.map(\.id))
        XCTAssertNotNil(room.shuffleRun)

        room.play(source)
        XCTAssertNil(room.shuffleRun)
    }
}

private struct ShuffleArtistSearch: ArtistSearchServicing {
    func searchArtists(query: String) async throws -> [RecognizedArtist] { [] }
}
