import XCTest
@testable import BeforeShow

@MainActor
final class ListeningVideoDockTests: XCTestCase {
    private struct NoStreamSearch: ArtistVideoSearching {
        func videos(for artist: String) async throws -> [ArtistVideo] { [] }
        func stream(for bvid: String) async throws -> ArtistVideoStream { throw CancellationError() }
    }

    private func openedDock() -> ListeningVideoDock {
        let dock = ListeningVideoDock(search: NoStreamSearch())
        let video = ArtistVideo(bvid: "BV1", title: "Live", author: "a", playCount: 0, duration: "3:00", coverURL: nil)
        dock.open(ListeningVideoSelection(artist: "a", video: video, related: []))
        return dock
    }

    override func tearDown() async throws {
        AppAudioSession.resetForTests()
        await AppAudioSession.waitForPendingOperations()
        try await super.tearDown()
    }

    func testMusicTakingFocusHandsTheMiniPlayerBackToMusic() {
        let dock = openedDock()
        AppAudioSession.claimFocus(.listening)
        XCTAssertFalse(dock.hasVideo)
    }

    func testOtherSoundOnlyPausesTheVideo() {
        let dock = openedDock()
        AppAudioSession.claimFocus(.memoryVideo)
        XCTAssertTrue(dock.hasVideo)
        dock.close()
    }
}
