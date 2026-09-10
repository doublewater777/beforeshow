import XCTest
@testable import BeforeShow

@MainActor
final class ListeningDisplayProjectionTests: XCTestCase {
    func testMetadataOnlyCatalogNeverPromisesPreviewAndAlbumOpensAppleMusic() {
        let url = URL(string: "https://music.apple.com/album/example")!
        let disc = ListeningDisc(
            id: "album",
            title: "Album",
            artworkURL: nil,
            tracks: [track("metadata", preview: false)],
            appleMusicURL: url
        )
        let projection = makeProjection(
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: false),
            discs: [disc]
        )

        XCTAssertEqual(projection.roomMode, .metadataOnly)
        let state = projection.discPresentation(for: disc)
        XCTAssertEqual(state.capability, .metadataOnly)
        XCTAssertNil(state.defaultPlayableTrackID)
        XCTAssertEqual(state.primaryAction, .openAppleMusic(url))
        XCTAssertFalse(state.canLoad)
    }

    func testMixedPreviewDiscUsesFirstPlayableTrackAndExplainsPartialPreview() {
        let first = track("metadata", preview: false)
        let second = track("preview", preview: true)
        let disc = ListeningDisc(id: "mixed", title: "Mixed", artworkURL: nil, tracks: [first, second])
        let projection = makeProjection(
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: false),
            discs: [disc]
        )

        XCTAssertEqual(projection.roomMode, .preview)
        let state = projection.discPresentation(for: disc)
        XCTAssertEqual(state.capability, .previewOnly)
        XCTAssertTrue(state.hasPartialPreview)
        XCTAssertEqual(state.defaultPlayableTrackID, "preview")
        XCTAssertEqual(state.primaryAction, .load(songID: "preview"))
        XCTAssertFalse(projection.trackPresentation(for: first).isPlayable)
        XCTAssertTrue(projection.trackPresentation(for: second).isPlayable)
    }

    func testFullCatalogPlaybackWinsAndStartsAtStableFirstTrack() {
        let first = track("first", preview: false)
        let second = track("second", preview: true)
        let disc = ListeningDisc(id: "full", title: "Full", artworkURL: nil, tracks: [first, second])
        let projection = makeProjection(
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: true),
            discs: [disc]
        )

        XCTAssertEqual(projection.roomMode, .fullPlayback)
        let state = projection.discPresentation(for: disc)
        XCTAssertEqual(state.capability, .fullPlayback)
        XCTAssertEqual(state.defaultPlayableTrackID, "first")
        XCTAssertEqual(state.primaryAction, .load(songID: "first"))
    }

    func testEmptyDiscIsUnavailableAndCannotEnterPlayer() {
        let disc = ListeningDisc(id: "empty", title: "Empty", artworkURL: nil, tracks: [])
        let projection = makeProjection(
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: false),
            discs: [disc]
        )

        XCTAssertEqual(projection.roomMode, .unavailable)
        XCTAssertEqual(projection.discPresentation(for: disc).primaryAction, .unavailable)
        XCTAssertFalse(projection.discPresentation(for: disc).canLoad)
    }

    func testShelfShowsFourAndOnlyOffersAllDiscsWhenThereIsOverflow() {
        let discs = (0..<5).map { index in
            ListeningDisc(
                id: "disc-\(index)",
                title: "Disc \(index)",
                artworkURL: nil,
                tracks: [track("song-\(index)", preview: true)]
            )
        }
        let five = makeProjection(
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: false),
            discs: discs,
            libraryDiscs: discs
        )
        let four = makeProjection(
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: false),
            discs: Array(discs.prefix(4)),
            libraryDiscs: Array(discs.prefix(4))
        )

        XCTAssertEqual(five.shelfDiscs.map(\.id), ["disc-0", "disc-1", "disc-2", "disc-3"])
        XCTAssertTrue(five.showsAllDiscs)
        XCTAssertEqual(four.shelfDiscs.count, 4)
        XCTAssertFalse(four.showsAllDiscs)
    }

    func testAuthorizationAndCacheRecoveryStaySeparateFromRoomCapability() {
        let disc = ListeningDisc(
            id: "preview",
            title: "Preview",
            artworkURL: nil,
            tracks: [track("preview", preview: true)]
        )
        let denied = makeProjection(
            page: .ready,
            access: .init(authorizationStatus: .denied, canPlayCatalogContent: false),
            discs: [disc]
        )
        let cachedError = makeProjection(
            page: .cachedWithError,
            access: .init(authorizationStatus: .authorized, canPlayCatalogContent: false),
            discs: [disc]
        )

        XCTAssertEqual(denied.roomMode, .preview)
        XCTAssertEqual(denied.recoveryAction, .openSettings)
        XCTAssertEqual(cachedError.roomMode, .preview)
        XCTAssertEqual(cachedError.recoveryAction, .retryCatalog)
    }

    func testPreviewPlayerReportsRemainingTimeAndFailureExposesRetry() {
        let disc = ListeningDisc(
            id: "preview",
            title: "Preview",
            artworkURL: nil,
            tracks: [track("preview", preview: true, duration: 30)]
        )
        let access = ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: false)
        let playing = ListeningDisplayProjector.make(
            page: .ready,
            access: access,
            isAuthorizing: false,
            allDiscs: [disc],
            libraryDiscs: [disc],
            loadedDisc: disc,
            isDiscSeated: true,
            isLidClosed: true,
            currentTrack: disc.tracks[0],
            playbackState: .playing(songID: "preview", source: .preview, currentTime: 18, duration: 30),
            playbackError: nil
        )
        let failed = ListeningDisplayProjector.make(
            page: .ready,
            access: access,
            isAuthorizing: false,
            allDiscs: [disc],
            libraryDiscs: [disc],
            loadedDisc: disc,
            isDiscSeated: true,
            isLidClosed: true,
            currentTrack: disc.tracks[0],
            playbackState: .failed,
            playbackError: nil
        )

        XCTAssertEqual(playing.player.phase, .playing)
        XCTAssertEqual(playing.player.source, .preview)
        XCTAssertEqual(playing.player.previewRemaining, 12)
        XCTAssertTrue(playing.player.canPlayPause)
        XCTAssertEqual(failed.player.phase, .failed)
        XCTAssertEqual(failed.player.recoveryAction, .retryPlayback)
        XCTAssertFalse(failed.player.canPlayPause)
    }

    func testNoDiscGuidanceDependsOnRealRoomCapability() {
        let metadata = ListeningDisc(
            id: "metadata",
            title: "Metadata",
            artworkURL: nil,
            tracks: [track("metadata", preview: false)]
        )
        let preview = ListeningDisc(
            id: "preview",
            title: "Preview",
            artworkURL: nil,
            tracks: [track("preview", preview: true)]
        )
        let access = ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: false)

        XCTAssertEqual(makeProjection(access: access, discs: [metadata]).player.phase, .noDisc)
        XCTAssertEqual(makeProjection(access: access, discs: [metadata]).roomMode, .metadataOnly)
        XCTAssertEqual(makeProjection(access: access, discs: [preview]).roomMode, .preview)
    }

    private func makeProjection(
        page: ListeningPresentation = .ready,
        access: ListeningMusicAccess,
        discs: [ListeningDisc],
        libraryDiscs: [ListeningDisc]? = nil
    ) -> ListeningDisplayProjection {
        ListeningDisplayProjector.make(
            page: page,
            access: access,
            isAuthorizing: false,
            allDiscs: discs,
            libraryDiscs: libraryDiscs ?? discs,
            loadedDisc: nil,
            isDiscSeated: false,
            isLidClosed: true,
            currentTrack: nil,
            playbackState: .idle,
            playbackError: nil
        )
    }

    private func track(_ id: String, preview: Bool, duration: TimeInterval? = 30) -> ListeningDiscTrack {
        ListeningDiscTrack(
            CatalogSong(
                appleMusicSongID: id,
                title: id,
                artistName: "Artist",
                duration: duration,
                previewURL: preview ? "https://example.invalid/\(id).m4a" : nil
            )
        )
    }
}
