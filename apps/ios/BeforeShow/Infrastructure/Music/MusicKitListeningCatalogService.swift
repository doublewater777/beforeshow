import Foundation
import MusicKit

struct MusicKitListeningCatalogService: ListeningMusicCatalogServicing {
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
        Self.appendAlbums(fullAlbums, isCompilation: false, to: &albumSources, seenIDs: &seenAlbumIDs)
        Self.appendAlbums(albums, isCompilation: false, to: &albumSources, seenIDs: &seenAlbumIDs)
        Self.appendAlbums(singles, isCompilation: false, to: &albumSources, seenIDs: &seenAlbumIDs)
        Self.appendAlbums(compilationAlbums, isCompilation: true, to: &albumSources, seenIDs: &seenAlbumIDs)

        var baseSongsByID: [String: Song] = [:]
        let topSongIDs = Self.deduplicated(topSongs.map { song in
            baseSongsByID[song.id.rawValue] = song
            return song.id.rawValue
        })

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

        var trustedTargetSongIDs = Set(topSongIDs)
        for album in detailedAlbums where !album.isCompilation {
            trustedTargetSongIDs.formUnion(album.songs.map { $0.id.rawValue })
        }

        var songPayloadsByID: [String: ListeningCatalogSongPayload] = [:]
        for songID in requestedSongIDs {
            guard let song = enrichedSongs[songID] else {
                throw ListeningCatalogError.incompleteCatalog(songID)
            }
            let fallbackAlbum = detailedAlbums
                .first(where: { !$0.isCompilation && $0.containsSong(songID) })?.album
                ?? detailedAlbums.first(where: { $0.containsSong(songID) })?.album
            songPayloadsByID[songID] = Self.songPayload(
                from: song,
                targetArtistID: artistID,
                fallbackAlbum: fallbackAlbum,
                assumesTargetArtistWhenRelationshipMissing: trustedTargetSongIDs.contains(songID)
            )
        }

        let albumCandidates = detailedAlbums.map { detailedAlbum in
            ListeningCatalogAlbumCandidate(
                albumID: detailedAlbum.album.id.rawValue,
                isCompilation: detailedAlbum.isCompilation,
                tracks: detailedAlbum.songs.compactMap { song in
                    guard let payload = songPayloadsByID[song.id.rawValue] else { return nil }
                    return ListeningCatalogTrackCandidate(
                        songID: payload.songID,
                        performerArtistIDs: payload.performerArtistIDs
                    )
                }
            )
        }
        let assembly = ListeningCatalogAssemblyPolicy.assemble(
            targetArtistID: artistID,
            topSongIDs: topSongIDs,
            albums: albumCandidates
        )

        var albumPayloads: [ListeningCatalogAlbumPayload] = []
        for detailedAlbum in detailedAlbums {
            let albumID = detailedAlbum.album.id.rawValue
            guard assembly.retainedAlbumIDs.contains(albumID),
                  let orderedTrackIDs = assembly.retainedTrackIDsByAlbumID[albumID] else {
                continue
            }
            let albumArtistIDs: [String]
            if let albumArtists = detailedAlbum.album.artists {
                albumArtistIDs = Array(albumArtists).map(\.id.rawValue)
            } else {
                albumArtistIDs = []
            }
            albumPayloads.append(ListeningCatalogAlbumPayload(
                albumID: albumID,
                title: detailedAlbum.album.title,
                artworkURL: Self.artworkURL(detailedAlbum.album.artwork),
                releaseDate: detailedAlbum.album.releaseDate,
                artistIDs: albumArtistIDs,
                orderedTrackIDs: orderedTrackIDs
            ))
        }

        let retainedSongPayloads = assembly.orderedSongIDs.compactMap { songPayloadsByID[$0] }
        guard retainedSongPayloads.count == assembly.orderedSongIDs.count else {
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
            orderedSongIDs: assembly.orderedSongIDs,
            topSongIDs: topSongIDs,
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

        // iOS 17 MusicKit doesn't expose a catalog request `properties` surface for
        // relationship expansion. Fetch each stable ID with an explicit equality
        // filter, then load the Song relationships through MusicItem.with(_:).
        for rawID in songIDs {
            let musicID = MusicItemID(rawID)
            var request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: musicID
            )
            request.limit = 1
            let response = try await request.response()

            let baseSong: Song
            if let fetchedSong = response.items.first {
                baseSong = fetchedSong
            } else if let fallback = baseSongsByID[rawID] {
                baseSong = fallback
            } else {
                throw ListeningCatalogError.incompleteCatalog(rawID)
            }

            result[rawID] = try await baseSong.with([.artists, .albums])
        }
        return result
    }

    private static func songPayload(
        from song: Song,
        targetArtistID: String,
        fallbackAlbum: Album?,
        assumesTargetArtistWhenRelationshipMissing: Bool
    ) -> ListeningCatalogSongPayload {
        var performerArtistIDs: [String] = []
        var performerArtistNames: [String] = []
        if let artists = song.artists {
            let values = Array(artists)
            performerArtistIDs = values.map(\.id.rawValue)
            performerArtistNames = values.map(\.name)
        }
        if performerArtistIDs.isEmpty, assumesTargetArtistWhenRelationshipMissing {
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

    func containsSong(_ songID: String) -> Bool {
        songs.contains { $0.id.rawValue == songID }
    }
}
