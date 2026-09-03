import Foundation
import MusicKit

struct MusicKitListeningCatalogService: ListeningMusicCatalogServicing {
    private let songBatchSize = 25

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus {
        Self.authorizationStatus(from: MusicAuthorization.currentStatus)
    }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        Self.authorizationStatus(from: await MusicAuthorization.request())
    }

    func currentAccess() async -> ListeningMusicAccess {
        let authorizationStatus = currentAuthorizationStatus()
        guard authorizationStatus == .authorized else {
            return ListeningMusicAccess(
                authorizationStatus: authorizationStatus,
                canPlayCatalogContent: false
            )
        }
        let canPlayCatalogContent = (try? await MusicSubscription.current.canPlayCatalogContent) ?? false
        return ListeningMusicAccess(
            authorizationStatus: authorizationStatus,
            canPlayCatalogContent: canPlayCatalogContent
        )
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date = Date()
    ) async throws -> ListeningArtistCatalogPayload {
        guard currentAuthorizationStatus() == .authorized else {
            throw ListeningCatalogError.authorizationRequired
        }

        let musicArtistID = MusicItemID(artistID)
        var request = MusicCatalogResourceRequest<Artist>(
            matching: \.id,
            equalTo: musicArtistID
        )
        request.limit = 1
        let response = try await request.response()
        guard let baseArtist = response.items.first else {
            throw ListeningCatalogError.artistNotFound(artistID)
        }

        let artist = try await baseArtist.with([
            .topSongs,
            .fullAlbums,
            .albums,
            .singles,
            .compilationAlbums
        ])

        let topSongs = try await Self.allItems(from: artist.topSongs)
        let fullAlbums = try await Self.allItems(from: artist.fullAlbums)
        let albums = try await Self.allItems(from: artist.albums)
        let singles = try await Self.allItems(from: artist.singles)
        let compilationAlbums = try await Self.allItems(from: artist.compilationAlbums)

        var albumSources: [AlbumSource] = []
        var seenAlbumIDs = Set<String>()
        appendAlbums(fullAlbums, isCompilation: false, to: &albumSources, seenIDs: &seenAlbumIDs)
        appendAlbums(albums, isCompilation: false, to: &albumSources, seenIDs: &seenAlbumIDs)
        appendAlbums(singles, isCompilation: false, to: &albumSources, seenIDs: &seenAlbumIDs)
        appendAlbums(compilationAlbums, isCompilation: true, to: &albumSources, seenIDs: &seenAlbumIDs)

        var baseSongsByID: [String: Song] = [:]
        var topSongIDs: [String] = []
        for song in topSongs {
            let id = song.id.rawValue
            baseSongsByID[id] = song
            if !topSongIDs.contains(id) {
                topSongIDs.append(id)
            }
        }

        var detailedAlbums: [DetailedAlbum] = []
        for source in albumSources {
            let detailed = try await source.album.with([.tracks, .artists])
            let tracks = try await Self.allItems(from: detailed.tracks)
            let songs = tracks.compactMap { track -> Song? in
                guard case let .song(song) = track else { return nil }
                return song
            }
            for song in songs {
                baseSongsByID[song.id.rawValue] = song
            }
            detailedAlbums.append(DetailedAlbum(
                album: detailed,
                isCompilation: source.isCompilation,
                songs: songs
            ))
        }

        let requestedSongIDs = Self.uniqueSongIDs(
            topSongIDs: topSongIDs,
            albums: detailedAlbums
        )
        let enrichedSongs = try await fetchEnrichedSongs(
            songIDs: requestedSongIDs,
            baseSongsByID: baseSongsByID
        )

        var songPayloadsByID: [String: ListeningCatalogSongPayload] = [:]
        for songID in requestedSongIDs {
            guard let song = enrichedSongs[songID] else {
                throw ListeningCatalogError.incompleteCatalog(songID)
            }
            songPayloadsByID[songID] = Self.songPayload(
                from: song,
                targetArtistID: artistID,
                fallbackAlbum: detailedAlbums.first(where: { detail in
                    detail.songs.contains(where: { $0.id.rawValue == songID })
                })?.album
            )
        }

        var albumPayloads: [ListeningCatalogAlbumPayload] = []
        var retainedAlbumSongIDs: [String] = []
        for detailedAlbum in detailedAlbums {
            let albumArtistIDs = detailedAlbum.album.artists?.map(\.id.rawValue) ?? []
            var trackIDs: [String] = []
            for song in detailedAlbum.songs {
                let songID = song.id.rawValue
                guard let payload = songPayloadsByID[songID] else { continue }
                if detailedAlbum.isCompilation,
                   !payload.performerArtistIDs.contains(artistID) {
                    continue
                }
                if !trackIDs.contains(songID) {
                    trackIDs.append(songID)
                }
            }
            if detailedAlbum.isCompilation, trackIDs.isEmpty {
                continue
            }
            retainedAlbumSongIDs.append(contentsOf: trackIDs)
            albumPayloads.append(ListeningCatalogAlbumPayload(
                albumID: detailedAlbum.album.id.rawValue,
                title: detailedAlbum.album.title,
                artworkURL: Self.artworkURL(detailedAlbum.album.artwork),
                releaseDate: detailedAlbum.album.releaseDate,
                artistIDs: albumArtistIDs,
                orderedTrackIDs: trackIDs
            ))
        }

        let orderedSongIDs = Self.deduplicated(topSongIDs + retainedAlbumSongIDs)
        let retainedSongPayloads = orderedSongIDs.compactMap { songPayloadsByID[$0] }
        guard retainedSongPayloads.count == orderedSongIDs.count else {
            throw ListeningCatalogError.incompleteCatalog(artistID)
        }

        return ListeningArtistCatalogPayload(
            artistID: artistID,
            artistName: artist.name,
            artworkURL: Self.artworkURL(artist.artwork),
            editorialText: artist.editorialNotes?.standard
                ?? artist.editorialNotes?.short
                ?? artist.editorialNotes?.tagline,
            genreNames: artist.genreNames ?? [],
            orderedSongIDs: orderedSongIDs,
            topSongIDs: topSongIDs.filter { songPayloadsByID[$0] != nil },
            albumIDs: albumPayloads.map(\.albumID),
            songs: retainedSongPayloads,
            albums: albumPayloads,
            fetchedAt: fetchedAt
        )
    }

    private func fetchEnrichedSongs(
        songIDs: [String],
        baseSongsByID: [String: Song]
    ) async throws -> [String: Song] {
        var result: [String: Song] = [:]
        for chunk in songIDs.chunked(into: songBatchSize) {
            let musicIDs = chunk.map(MusicItemID.init)
            var request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                memberOf: musicIDs
            )
            request.limit = chunk.count
            request.properties = [.artists, .albums]
            let response = try await request.response()

            for rawID in chunk {
                let id = MusicItemID(rawID)
                if let song = response.item(for: id) {
                    result[rawID] = song
                    continue
                }
                guard let baseSong = baseSongsByID[rawID] else {
                    throw ListeningCatalogError.incompleteCatalog(rawID)
                }
                result[rawID] = try await baseSong.with([.artists, .albums])
            }
        }
        return result
    }

    private static func songPayload(
        from song: Song,
        targetArtistID: String,
        fallbackAlbum: Album?
    ) -> ListeningCatalogSongPayload {
        let artists = song.artists.map(Array.init) ?? []
        var performerArtistIDs = artists.map(\.id.rawValue)
        var performerArtistNames = artists.map(\.name)
        if performerArtistIDs.isEmpty,
           let fallbackArtists = fallbackAlbum?.artists.map(Array.init),
           !fallbackArtists.isEmpty {
            performerArtistIDs = fallbackArtists.map(\.id.rawValue)
            performerArtistNames = fallbackArtists.map(\.name)
        }
        if performerArtistIDs.isEmpty, song.artistName == fallbackAlbum?.artistName {
            performerArtistIDs = [targetArtistID]
            performerArtistNames = [song.artistName]
        }

        let album = song.albums?.first ?? fallbackAlbum
        return ListeningCatalogSongPayload(
            songID: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            albumID: album?.id.rawValue,
            albumTitle: song.albumTitle ?? album?.title,
            artworkURL: Self.artworkURL(song.artwork ?? album?.artwork),
            duration: song.duration,
            performerArtistIDs: performerArtistIDs,
            performerArtistNames: performerArtistNames,
            previewURL: song.previewAssets?.first?.url?.absoluteString
                ?? song.previewAssets?.first?.hlsURL?.absoluteString
        )
    }

    private static func appendAlbums(
        _ albums: [Album],
        isCompilation: Bool,
        to result: inout [AlbumSource],
        seenIDs: inout Set<String>
    ) {
        for album in albums where seenIDs.insert(album.id.rawValue).inserted {
            result.append(AlbumSource(album: album, isCompilation: isCompilation))
        }
    }

    private static func uniqueSongIDs(
        topSongIDs: [String],
        albums: [DetailedAlbum]
    ) -> [String] {
        deduplicated(
            topSongIDs + albums.flatMap { detail in
                detail.songs.map { $0.id.rawValue }
            }
        )
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func allItems<Item>(
        from collection: MusicItemCollection<Item>?
    ) async throws -> [Item] where Item: MusicItem, Item: Decodable {
        guard var collection else { return [] }
        while collection.hasNextBatch {
            guard let next = try await collection.nextBatch() else { break }
            collection += next
        }
        return Array(collection)
    }

    private static func artworkURL(_ artwork: Artwork?) -> String? {
        artwork?.url(width: 600, height: 600)?.absoluteString
    }

    private static func authorizationStatus(
        from status: MusicAuthorization.Status
    ) -> ListeningMusicAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .authorized
        @unknown default: return .restricted
        }
    }
}

private struct AlbumSource {
    let album: Album
    let isCompilation: Bool
}

private struct DetailedAlbum {
    let album: Album
    let isCompilation: Bool
    let songs: [Song]
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
