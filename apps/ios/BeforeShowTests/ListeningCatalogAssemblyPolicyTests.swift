import XCTest
@testable import BeforeShow

final class ListeningCatalogAssemblyPolicyTests: XCTestCase {
    func testTopSongsLeadAndAlbumOrderIsStableWithGlobalDedupe() {
        let result = ListeningCatalogAssemblyPolicy.assemble(
            targetArtistID: "artist-1",
            topSongIDs: ["top-1", "shared", "top-1"],
            albums: [
                ListeningCatalogAlbumCandidate(
                    albumID: "full",
                    isCompilation: false,
                    tracks: [
                        .init(songID: "shared", performerArtistIDs: ["artist-1"]),
                        .init(songID: "full-2", performerArtistIDs: ["artist-1"])
                    ]
                ),
                ListeningCatalogAlbumCandidate(
                    albumID: "single",
                    isCompilation: false,
                    tracks: [
                        .init(songID: "single-1", performerArtistIDs: ["artist-1"]),
                        .init(songID: "full-2", performerArtistIDs: ["artist-1"])
                    ]
                )
            ]
        )

        XCTAssertEqual(result.orderedSongIDs, ["top-1", "shared", "full-2", "single-1"])
        XCTAssertEqual(result.retainedAlbumIDs, ["full", "single"])
        XCTAssertEqual(result.retainedTrackIDsByAlbumID["full"], ["shared", "full-2"])
        XCTAssertEqual(result.retainedTrackIDsByAlbumID["single"], ["single-1", "full-2"])
    }

    func testCompilationKeepsOnlyTracksWhosePerformerIDsContainTargetArtist() {
        let result = ListeningCatalogAssemblyPolicy.assemble(
            targetArtistID: "artist-1",
            topSongIDs: [],
            albums: [
                ListeningCatalogAlbumCandidate(
                    albumID: "compilation",
                    isCompilation: true,
                    tracks: [
                        .init(songID: "target-song", performerArtistIDs: ["artist-1", "guest"]),
                        .init(songID: "other-song", performerArtistIDs: ["artist-2"]),
                        .init(songID: "unknown-song", performerArtistIDs: [])
                    ]
                )
            ]
        )

        XCTAssertEqual(result.orderedSongIDs, ["target-song"])
        XCTAssertEqual(result.retainedAlbumIDs, ["compilation"])
        XCTAssertEqual(result.retainedTrackIDsByAlbumID["compilation"], ["target-song"])
    }

    func testCompilationWithNoTargetTracksIsExcludedCompletely() {
        let result = ListeningCatalogAssemblyPolicy.assemble(
            targetArtistID: "artist-1",
            topSongIDs: ["top"],
            albums: [
                ListeningCatalogAlbumCandidate(
                    albumID: "irrelevant-compilation",
                    isCompilation: true,
                    tracks: [
                        .init(songID: "other", performerArtistIDs: ["artist-2"])
                    ]
                )
            ]
        )

        XCTAssertEqual(result.orderedSongIDs, ["top"])
        XCTAssertTrue(result.retainedAlbumIDs.isEmpty)
        XCTAssertTrue(result.retainedTrackIDsByAlbumID.isEmpty)
    }

    func testNonCompilationDoesNotRequirePerformerRelationshipToRetainTracks() {
        let result = ListeningCatalogAssemblyPolicy.assemble(
            targetArtistID: "artist-1",
            topSongIDs: [],
            albums: [
                ListeningCatalogAlbumCandidate(
                    albumID: "album",
                    isCompilation: false,
                    tracks: [
                        .init(songID: "relationship-missing", performerArtistIDs: [])
                    ]
                )
            ]
        )

        XCTAssertEqual(result.orderedSongIDs, ["relationship-missing"])
        XCTAssertEqual(result.retainedAlbumIDs, ["album"])
    }
}
