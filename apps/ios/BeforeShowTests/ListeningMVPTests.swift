import SwiftData
import XCTest
@testable import BeforeShow

@MainActor final class ListeningMVPTests: XCTestCase {
    func testAlbumsAreMultiTrackContainersAndHonorTrackOrder() {
        let songs = [CatalogSong(appleMusicSongID: "a", title: "A", artistName: "Artist"),
                     CatalogSong(appleMusicSongID: "b", title: "B", artistName: "Artist")]
        let album = CatalogAlbum(appleMusicAlbumID: "album", title: "Album", orderedTrackIDs: ["b", "a"])
        let discs = ListeningDiscAssembler.discs(albums: [album], songs: songs)
        XCTAssertEqual(discs.count, 1)
        XCTAssertEqual(discs[0].tracks.map(\.id), ["b", "a"])
    }
    func testAlbumMetadataIsCarriedToItsDisc() {
        let song = CatalogSong(appleMusicSongID: "song", title: "Song", artistName: "Artist")
        let album = CatalogAlbum(
            appleMusicAlbumID: "album", title: "Album", artistNames: ["Artist"],
            editorialText: "Editorial", genreNames: ["Pop"], recordLabelName: "Label",
            contentRatingRawValue: "explicit", audioVariantRawValues: ["lossless"],
            isAppleDigitalMaster: true, appleMusicURL: "https://music.apple.com/example",
            orderedTrackIDs: ["song"]
        )

        let disc = ListeningDiscAssembler.discs(albums: [album], songs: [song])[0]

        XCTAssertEqual(disc.artistNames, ["Artist"])
        XCTAssertEqual(disc.editorialText, "Editorial")
        XCTAssertEqual(disc.genreNames, ["Pop"])
        XCTAssertEqual(disc.recordLabelName, "Label")
        XCTAssertEqual(disc.contentRatingRawValue, "explicit")
        XCTAssertEqual(disc.audioVariantRawValues, ["lossless"])
        XCTAssertTrue(disc.isAppleDigitalMaster == true)
        XCTAssertEqual(disc.appleMusicURL, URL(string: "https://music.apple.com/example"))
    }
}

@MainActor final class ListeningRoomPlaybackTests: XCTestCase {
    func testPreviewContinuesWithinDiscAndStopsAtLastTrackWithoutEvidence() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Fixture", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        context.insert(show)
        for id in ["a", "b"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist", duration: 1,
                                      previewURL: "https://example.invalid/\(id).m4a"))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist", orderedSongIDs: ["a", "b"], topSongIDs: ["a", "b"]))
        try context.save()
        let service = ListeningTestPlayer(source: .preview)
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningMVPCatalogStub(), playbackFactory: { _ in service })
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        defer { room.setActive(false) }
        room.loadDisc(disc)
        try await wait { room.hasLoadedDisc }
        try await wait { room.isPlaying }
        XCTAssertEqual(service.source, .preview)
        service.advanceNaturally()
        try await wait { room.trackIndex == 1 && room.isPlaying }
        XCTAssertEqual(service.loadedSongIDs, ["a", "b"])
        service.finishQueue()
        try await wait { !room.isPlaying && room.trackIndex == 0 }
        XCTAssertEqual(room.display.player.phase, .stopped, "playing through the disc stops it at its first track")
        XCTAssertEqual(room.loadedDisc?.id, disc.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 0)
        XCTAssertEqual(service.loadCount, 1)
        room.playPause()
        try await wait { room.isPlaying }
        XCTAssertEqual(service.loadCount, 2)
        XCTAssertEqual(service.loadedStartSongID, "a")
        XCTAssertEqual(service.loadedSongIDs, ["a", "b"])
        show.artists[0].appleMusicArtistID = "replacement-artist"
        await room.load(show: show)
        // Artist identity changes keep the loaded disc and the playback transport;
        // only the catalog around them reloads.
        XCTAssertEqual(room.loadedDisc?.id, disc.id)
        XCTAssertEqual(room.track?.id, "a")
        XCTAssertTrue(room.isPlaying)
    }
    func testSelectingAnotherTrackOnTheSeatedDiscDoesNotReloadMechanically() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Fixture", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        context.insert(show)
        for id in ["a", "b"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist", duration: 1,
                                      previewURL: "https://example.invalid/\(id).m4a"))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist", orderedSongIDs: ["a", "b"], topSongIDs: ["a", "b"]))
        try context.save()
        let service = ListeningTestPlayer(source: .preview)
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningMVPCatalogStub(), playbackFactory: { _ in service })
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        defer { room.setActive(false) }
        room.loadDisc(disc, songID: "a", autoplay: true)
        try await wait { room.hasLoadedDisc && room.isPlaying }
        room.loadDisc(disc, songID: "b", autoplay: true)
        try await wait { room.trackIndex == 1 && room.isPlaying }
        XCTAssertEqual(room.loadedDisc?.id, disc.id)
        XCTAssertEqual(service.loadedSongIDs, ["a", "b"])
        XCTAssertEqual(service.loadCount, 1, "selecting a track on the seated disc stays in its queue")
    }
    func testSwitchingDiscsWhilePlayingSwapsToTheReplacementOnTheTap() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Fixture", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        context.insert(show)
        let songA = CatalogSong(appleMusicSongID: "a", title: "a", artistName: "Artist", duration: 1,
                                previewURL: "https://example.invalid/a.m4a")
        let songB = CatalogSong(appleMusicSongID: "b", title: "b", artistName: "Artist", duration: 1,
                                previewURL: "https://example.invalid/b.m4a")
        context.insert(songA)
        context.insert(songB)
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist", orderedSongIDs: ["a", "b"], topSongIDs: ["a", "b"]))
        try context.save()
        let service = ListeningTestPlayer(source: .preview)
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningMVPCatalogStub(), playbackFactory: { _ in service })
        await room.load(show: show)
        let first = ListeningDisc(id: "first", title: "First", artworkURL: nil,
                                  tracks: [ListeningDiscTrack(songA)])
        let second = ListeningDisc(id: "second", title: "Second", artworkURL: nil,
                                   tracks: [ListeningDiscTrack(songB)])
        defer { room.setActive(false) }

        room.loadDisc(first)
        try await wait { room.loadedDisc?.id == first.id && room.isPlaying }

        room.loadDisc(second)
        XCTAssertEqual(room.loadedDisc?.id, second.id, "the new record is on the deck as soon as it is chosen")
        XCTAssertEqual(room.track?.id, "b")
        try await wait { room.isPlaying }

        XCTAssertEqual(service.loadCount, 2)
        XCTAssertEqual(service.loadedSongIDs, ["b"])
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the listening transition")
    }
}

private struct ListeningMVPCatalogStub: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: false) }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}
