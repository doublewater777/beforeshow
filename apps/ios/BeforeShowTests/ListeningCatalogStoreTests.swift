import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class ListeningCatalogStoreTests: XCTestCase {
    @MainActor
    func testInitialLoadPersistsCompleteCatalogPayload() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let service = StubListeningMusicCatalogService(payload: Self.payload(fetchedAt: now))
        let store = ListeningCatalogStore(modelContext: context, service: service)

        let snapshot = try await store.loadArtistCatalog(artistID: "artist-1", now: now)

        XCTAssertEqual(snapshot.artistName, "Artist One")
        XCTAssertEqual(snapshot.orderedSongIDs, ["song-top", "song-album"])
        XCTAssertEqual(snapshot.topSongIDs, ["song-top"])
        XCTAssertEqual(snapshot.albumIDs, ["album-1"])
        XCTAssertEqual(service.fetchCount, 1)

        let songs = try context.fetch(FetchDescriptor<CatalogSong>())
        let albums = try context.fetch(FetchDescriptor<CatalogAlbum>())
        XCTAssertEqual(songs.map(\.appleMusicSongID).sorted(), ["song-album", "song-top"])
        XCTAssertEqual(albums.map(\.appleMusicAlbumID), ["album-1"])
        XCTAssertEqual(
            songs.first(where: { $0.appleMusicSongID == "song-top" })?.previewURL,
            "https://example.com/preview.m4a"
        )
        let album = try XCTUnwrap(albums.first)
        XCTAssertEqual(album.editorialText, "Album editorial")
        XCTAssertEqual(album.genreNames, ["Pop", "Electronic"])
        XCTAssertEqual(album.recordLabelName, "Example Records")
        XCTAssertEqual(album.audioVariantRawValues, ["lossless", "dolbyAtmos"])
        XCTAssertEqual(album.appleMusicURL, "https://music.apple.com/example")
    }

    @MainActor
    func testFreshSnapshotDoesNotCallMusicKitAgain() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fetchedAt = now.addingTimeInterval(-60)
        try insertSnapshot(
            artistID: "artist-1",
            artistName: "Cached Artist",
            fetchedAt: fetchedAt,
            in: context
        )
        let service = StubListeningMusicCatalogService(payload: Self.payload(fetchedAt: now))
        let store = ListeningCatalogStore(modelContext: context, service: service)

        let snapshot = try await store.loadArtistCatalog(artistID: "artist-1", now: now)

        XCTAssertEqual(snapshot.artistName, "Cached Artist")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(service.fetchCount, 0)
    }

    @MainActor
    func testStaleSnapshotReturnsImmediatelyThenRevalidates() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldFetchedAt = now.addingTimeInterval(-(25 * 60 * 60))
        try insertSnapshot(
            artistID: "artist-1",
            artistName: "Cached Artist",
            fetchedAt: oldFetchedAt,
            in: context
        )
        let service = StubListeningMusicCatalogService(
            payload: Self.payload(fetchedAt: now),
            delayNanoseconds: 80_000_000
        )
        let store = ListeningCatalogStore(modelContext: context, service: service)

        let stale = try await store.loadArtistCatalog(artistID: "artist-1", now: now)
        XCTAssertEqual(stale.artistName, "Cached Artist")
        XCTAssertEqual(stale.fetchedAt, oldFetchedAt)

        try await Task.sleep(nanoseconds: 160_000_000)

        let refreshed = try XCTUnwrap(store.cachedSnapshot(artistID: "artist-1"))
        XCTAssertEqual(refreshed.artistName, "Artist One")
        XCTAssertEqual(refreshed.fetchedAt, now)
        XCTAssertEqual(service.fetchCount, 1)
    }

    @MainActor
    func testFailedRevalidationPreservesLastGoodSnapshot() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldFetchedAt = now.addingTimeInterval(-(25 * 60 * 60))
        try insertSnapshot(
            artistID: "artist-1",
            artistName: "Last Good",
            fetchedAt: oldFetchedAt,
            in: context
        )
        let service = StubListeningMusicCatalogService(
            error: ListeningCatalogError.incompleteCatalog("artist-1"),
            delayNanoseconds: 20_000_000
        )
        let store = ListeningCatalogStore(modelContext: context, service: service)

        _ = try await store.loadArtistCatalog(artistID: "artist-1", now: now)
        try await Task.sleep(nanoseconds: 80_000_000)

        let retained = try XCTUnwrap(store.cachedSnapshot(artistID: "artist-1"))
        XCTAssertEqual(retained.artistName, "Last Good")
        XCTAssertEqual(retained.fetchedAt, oldFetchedAt)
        XCTAssertEqual(service.fetchCount, 1)
    }

    @MainActor
    func testRefreshUpsertsInsteadOfBlindInsertingUniqueRows() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let firstAt = Date(timeIntervalSince1970: 2_000_000_000)
        let secondAt = firstAt.addingTimeInterval(90_000)
        let firstService = StubListeningMusicCatalogService(payload: Self.payload(fetchedAt: firstAt))
        let firstStore = ListeningCatalogStore(modelContext: context, service: firstService)
        _ = try await firstStore.refreshArtistCatalog(artistID: "artist-1", now: firstAt)

        let updatedPayload = Self.payload(
            fetchedAt: secondAt,
            artistName: "Artist One Updated"
        )
        let secondService = StubListeningMusicCatalogService(payload: updatedPayload)
        let secondStore = ListeningCatalogStore(modelContext: context, service: secondService)
        _ = try await secondStore.refreshArtistCatalog(artistID: "artist-1", now: secondAt)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ArtistCatalogSnapshot>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogSong>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CatalogAlbum>()), 1)
        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<ArtistCatalogSnapshot>()).first)
        XCTAssertEqual(snapshot.artistName, "Artist One Updated")
        XCTAssertEqual(snapshot.fetchedAt, secondAt)
    }

    @MainActor
    private func insertSnapshot(
        artistID: String,
        artistName: String,
        fetchedAt: Date,
        in context: ModelContext
    ) throws {
        let repository = ListeningRepository(modelContext: context)
        _ = try repository.upsertArtistCatalogSnapshot(
            artistID: artistID,
            artistName: artistName,
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: ["old-song"],
            topSongIDs: [],
            albumIDs: [],
            fetchedAt: fetchedAt
        )
        try context.save()
    }

    private static func payload(
        fetchedAt: Date,
        artistName: String = "Artist One"
    ) -> ListeningArtistCatalogPayload {
        ListeningArtistCatalogPayload(
            artistID: "artist-1",
            artistName: artistName,
            artworkURL: "https://example.com/artist.jpg",
            editorialText: "Editorial",
            genreNames: ["Pop"],
            orderedSongIDs: ["song-top", "song-album"],
            topSongIDs: ["song-top"],
            albumIDs: ["album-1"],
            songs: [
                ListeningCatalogSongPayload(
                    songID: "song-top",
                    title: "Top Song",
                    artistName: artistName,
                    albumID: "album-1",
                    albumTitle: "Album One",
                    artworkURL: "https://example.com/song.jpg",
                    duration: 210,
                    performerArtistIDs: ["artist-1"],
                    performerArtistNames: [artistName],
                    previewURL: "https://example.com/preview.m4a"
                ),
                ListeningCatalogSongPayload(
                    songID: "song-album",
                    title: "Album Song",
                    artistName: artistName,
                    albumID: "album-1",
                    albumTitle: "Album One",
                    artworkURL: nil,
                    duration: 180,
                    performerArtistIDs: ["artist-1"],
                    performerArtistNames: [artistName],
                    previewURL: nil
                )
            ],
            albums: [
                ListeningCatalogAlbumPayload(
                    albumID: "album-1",
                    title: "Album One",
                    artworkURL: "https://example.com/album.jpg",
                    releaseDate: fetchedAt.addingTimeInterval(-86_400),
                    artistIDs: ["artist-1"],
                    artistNames: [artistName],
                    editorialText: "Album editorial",
                    genreNames: ["Pop", "Electronic"],
                    copyright: "℗ 2026 Example Records",
                    recordLabelName: "Example Records",
                    contentRatingRawValue: "explicit",
                    audioVariantRawValues: ["lossless", "dolbyAtmos"],
                    isAppleDigitalMaster: true,
                    isCompilation: false,
                    isSingle: false,
                    appleMusicURL: "https://music.apple.com/example",
                    orderedTrackIDs: ["song-album"]
                )
            ],
            fetchedAt: fetchedAt
        )
    }
}

private final class StubListeningMusicCatalogService: ListeningMusicCatalogServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let payload: ListeningArtistCatalogPayload?
    private let error: Error?
    private let delayNanoseconds: UInt64
    private var storedFetchCount = 0

    init(
        payload: ListeningArtistCatalogPayload? = nil,
        error: Error? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.payload = payload
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    var fetchCount: Int {
        lock.withLock { storedFetchCount }
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        .authorized
    }

    func currentAccess() async -> ListeningMusicAccess {
        ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        lock.withLock { storedFetchCount += 1 }

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error { throw error }
        guard let payload else {
            throw ListeningCatalogError.artistNotFound(artistID)
        }
        return ListeningArtistCatalogPayload(
            artistID: payload.artistID,
            artistName: payload.artistName,
            artworkURL: payload.artworkURL,
            editorialText: payload.editorialText,
            genreNames: payload.genreNames,
            orderedSongIDs: payload.orderedSongIDs,
            topSongIDs: payload.topSongIDs,
            albumIDs: payload.albumIDs,
            songs: payload.songs,
            albums: payload.albums,
            fetchedAt: fetchedAt
        )
    }
}
