import XCTest
@testable import BeforeShow

@MainActor
final class FootprintNumberSongPlayerTests: XCTestCase {
    private let song = FootprintNumberSong(number: 7, title: "Seven", artist: "Band", trackID: 77)

    func testClosingTheRecordWhileItIsStillLoadingKeepsItSilent() async {
        let player = ListeningTestPlayer(source: .preview)
        let controller = FootprintNumberSongPlayer(player: player, lookup: Self.slowLookup)
        let tap = Task { await controller.toggle(song) }
        await Task.yield()
        XCTAssertEqual(controller.loadingNumber, 7)

        controller.stop(7)
        await tap.value

        XCTAssertEqual(player.playCount, 0)
        XCTAssertNil(controller.loadingNumber)
        XCTAssertNil(controller.currentNumber)
    }

    func testLeavingTheWallWhileARecordIsLoadingKeepsItSilent() async {
        let player = ListeningTestPlayer(source: .preview)
        let controller = FootprintNumberSongPlayer(player: player, lookup: Self.slowLookup)
        let tap = Task { await controller.toggle(song) }
        await Task.yield()

        controller.stopAll()
        await tap.value

        XCTAssertEqual(player.playCount, 0)
    }

    func testTappingAPausedRecordPicksUpWhereItStopped() async {
        let player = ListeningTestPlayer(source: .preview)
        let controller = FootprintNumberSongPlayer(player: player, lookup: Self.lookup)
        await controller.toggle(song)
        XCTAssertTrue(controller.isPlaying(7))

        await controller.toggle(song)
        XCTAssertTrue(controller.isPaused(7))
        await controller.toggle(song)

        XCTAssertEqual(player.loadCount, 1, "resumes instead of reloading from 0:00")
        XCTAssertTrue(controller.isPlaying(7))
    }

    func testAFinishedPreviewIsReportedSoItsAudioIsReleased() async {
        let player = ListeningTestPlayer(source: .preview)
        let controller = FootprintNumberSongPlayer(player: player, lookup: Self.lookup)
        await controller.toggle(song)
        player.hasEnded = true
        player.phase = .stopped

        XCTAssertTrue(controller.hasFinished)
        XCTAssertFalse(controller.isPaused(7))
        controller.stop(7)
        XCTAssertEqual(player.stopCount, 1)
        XCTAssertFalse(controller.hasFinished)
    }

    // MARK: Helpers

    private nonisolated static let preview = SongPreview(
        trackID: 77, title: "Seven", artist: "Band", album: nil, releaseYear: nil, genre: nil, duration: 30,
        previewURL: URL(string: "https://example.com/7.m4a")!, artworkURL: nil, storeURL: nil
    )

    private static let lookup: @Sendable ([Int]) async -> [Int: SongPreview] = { _ in [77: preview] }

    private static let slowLookup: @Sendable ([Int]) async -> [Int: SongPreview] = { _ in
        try? await Task.sleep(for: .milliseconds(200))
        return [77: preview]
    }
}
