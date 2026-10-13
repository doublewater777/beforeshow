import Foundation
import SwiftData

/// Owns a scoped read context and assembled artist catalogs for the bound room.
/// Runtime top-song arrivals and timetable edits reuse this durable projection.
@MainActor
final class ListeningCatalogProjection {
    private let source: ModelContext
    private let catalogStore: ListeningCatalogStore
    private var storeRevision = -1
    private var readContext: ModelContext?
    private var artistIDs: [String] = []
    private var dirty = true
    private var saveObserver: ListeningCatalogSaveObservation?
    private(set) var songs: [CatalogSong] = []
    private(set) var albums: [CatalogAlbum] = []
    private(set) var snapshots: [ArtistCatalogSnapshot] = []
    private(set) var artists: [String: ListeningArtistPresentation] = [:]
    private(set) var albumReleaseDates: [String: Date] = [:]
    private(set) var releaseDates: [String: Date] = [:]

    init(context: ModelContext, catalogStore: ListeningCatalogStore) {
        source = context
        self.catalogStore = catalogStore
        saveObserver = ListeningCatalogSaveObservation(NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let changed = self.source.insertedModelsArray + self.source.changedModelsArray
                    + self.source.deletedModelsArray
                if changed.contains(where: {
                    $0 is CatalogSong || $0 is CatalogAlbum || $0 is ArtistCatalogSnapshot
                }) { self.invalidate() }
            }
        })
    }

    private func invalidate() { dirty = true }

    func clear() {
        songs = []; albums = []; snapshots = []; artists = [:]; releaseDates = [:]; albumReleaseDates = [:]
        readContext = nil
        artistIDs = []
        dirty = true
    }

    /// Returns whether the durable catalog changed. Reentry does no song/album I/O.
    @discardableResult
    func refresh(artistIDs requested: [String]) throws -> Bool {
        let ids = Array(Set(requested)).sorted()
        guard dirty || ids != artistIDs || storeRevision != catalogStore.revision else { return false }
        let reader = ModelContext(source.container)
        let snapshots = try reader.fetch(FetchDescriptor<ArtistCatalogSnapshot>(
            predicate: #Predicate { ids.contains($0.artistID) }
        ))
        let albumIDs = Array(Set(snapshots.flatMap(\.albumIDs)))
        var albums = try reader.fetch(FetchDescriptor<CatalogAlbum>(
            predicate: #Predicate { albumIDs.contains($0.appleMusicAlbumID) }
        ))
        let playlists = Dictionary(snapshots.map { ($0.artistID, $0.featuredPlaylists) },
                                   uniquingKeysWith: { first, _ in first })
        let songIDs = Array(Set(snapshots.flatMap { $0.orderedSongIDs + $0.topSongIDs }
            + albums.flatMap(\.orderedTrackIDs)
            + playlists.values.flatMap { $0.flatMap(\.orderedTrackIDs) }))
        let songs = try reader.fetch(FetchDescriptor<CatalogSong>(
            predicate: #Predicate { songIDs.contains($0.appleMusicSongID) }
        ))
        // Top songs can reference an album outside the artist's release list.
        // Keep its date for the new-music compilation without retaining its tracks.
        let knownAlbumIDs = Set(albums.map(\.appleMusicAlbumID))
        let referencedAlbumIDs = Array(Set(songs.compactMap(\.albumID)).subtracting(knownAlbumIDs))
        if !referencedAlbumIDs.isEmpty {
            albums += try reader.fetch(FetchDescriptor<CatalogAlbum>(
                predicate: #Predicate { referencedAlbumIDs.contains($0.appleMusicAlbumID) }))
        }
        let byID = Dictionary(songs.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { a, _ in a })
        let albumsByID = Dictionary(albums.map { ($0.appleMusicAlbumID, $0) }, uniquingKeysWith: { a, _ in a })
        let tracks = byID.mapValues(ListeningDiscTrack.init)
        var artists: [String: ListeningArtistPresentation] = [:]
        for snapshot in snapshots {
            let discs = ListeningDiscAssembler.discs(featuredPlaylists: playlists[snapshot.artistID] ?? [],
                artistID: snapshot.artistID, songsByID: byID)
                + ListeningDiscAssembler.discs(albums: snapshot.albumIDs.compactMap { albumsByID[$0] }, songsByID: byID)
            artists[snapshot.artistID] = ListeningArtistPresentation(id: snapshot.artistID, name: snapshot.artistName,
                artworkURL: snapshot.artworkURL.flatMap(URL.init(string:)), editorialText: snapshot.editorialText,
                genres: snapshot.genreNames, top: snapshot.topSongIDs.compactMap { tracks[$0] },
                all: snapshot.orderedSongIDs.compactMap { tracks[$0] }, albums: discs)
        }
        self.songs = songs
        self.albums = albums
        self.snapshots = snapshots
        self.artists = artists
        albumReleaseDates = albumsByID.compactMapValues(\.releaseDate)
        releaseDates = byID.compactMapValues { song in song.albumID.flatMap { albumsByID[$0]?.releaseDate } }
        readContext = reader
        artistIDs = ids
        dirty = false
        storeRevision = catalogStore.revision
        return true
    }
}

private final class ListeningCatalogSaveObservation: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
