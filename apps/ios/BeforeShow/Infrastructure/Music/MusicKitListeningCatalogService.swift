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

    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        guard currentAuthorizationStatus() == .authorized else { throw ListeningCatalogError.authorizationRequired }
        var request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(artistID))
        request.limit = 1
        guard let artist = try await request.response().items.first else { return [] }
        let detailed = try await artist.with([.topSongs])
        return Array(detailed.topSongs ?? []).map {
            Self.songPayload(from: $0, targetArtistID: artistID, fallbackAlbum: nil, assumesTargetArtistWhenRelationshipMissing: true)
        }
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

        // Core enrichment contains only data required for the complete familiarity
        // denominator and release cabinet. Featured playlists are browse-only and are
        // fetched separately after the user selects an artist browsing scope.
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
        // Top-song and album-track responses already carry the playback metadata
        // needed here. Avoid refetching every song serially.
        let enrichedSongs = baseSongsByID

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
                artistNames: detailedAlbum.album.artists.map { Array($0).map(\.name) } ?? [],
                editorialText: detailedAlbum.album.editorialNotes?.standard
                    ?? detailedAlbum.album.editorialNotes?.short
                    ?? detailedAlbum.album.editorialNotes?.tagline,
                genreNames: detailedAlbum.album.genreNames,
                copyright: detailedAlbum.album.copyright,
                recordLabelName: detailedAlbum.album.recordLabelName,
                contentRatingRawValue: Self.contentRatingRawValue(detailedAlbum.album.contentRating),
                audioVariantRawValues: (detailedAlbum.album.audioVariants ?? []).map(Self.audioVariantRawValue),
                isAppleDigitalMaster: detailedAlbum.album.isAppleDigitalMaster,
                isCompilation: detailedAlbum.album.isCompilation,
                isSingle: detailedAlbum.album.isSingle,
                appleMusicURL: detailedAlbum.album.url?.absoluteString,
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
            featuredPlaylists: [],
            songs: retainedSongPayloads,
            albums: albumPayloads,
            fetchedAt: fetchedAt
        )
    }

    func fetchFeaturedPlaylists(
        artistID: String,
        fetchedAt: Date = Date()
    ) async throws -> ListeningFeaturedPlaylistsPayload {
        guard currentAuthorizationStatus() == .authorized else {
            throw ListeningCatalogError.authorizationRequired
        }

        var request = MusicCatalogResourceRequest<Artist>(
            matching: \.id,
            equalTo: MusicItemID(artistID)
        )
        request.limit = 1
        guard let baseArtist = try await request.response().items.first else {
            throw ListeningCatalogError.artistNotFound(artistID)
        }

        let artist = try await baseArtist.with([.featuredPlaylists])
        let featuredPlaylists = try await Self.allItems(from: artist.featuredPlaylists)
        var playlistPayloads: [ListeningCatalogPlaylistPayload] = []
        var songPayloadsByID: [String: ListeningCatalogSongPayload] = [:]

        for playlist in featuredPlaylists {
            let detailed = try await playlist.with([.tracks])
            let tracks = try await Self.allItems(from: detailed.tracks)
            let songs = tracks.compactMap { track -> Song? in
                guard case let .song(song) = track else { return nil }
                return song
            }
            guard !songs.isEmpty else { continue }

            for song in songs where songPayloadsByID[song.id.rawValue] == nil {
                songPayloadsByID[song.id.rawValue] = Self.songPayload(
                    from: song,
                    targetArtistID: artistID,
                    fallbackAlbum: nil,
                    assumesTargetArtistWhenRelationshipMissing: false
                )
            }
            playlistPayloads.append(ListeningCatalogPlaylistPayload(
                playlistID: detailed.id.rawValue,
                name: detailed.name,
                artworkURL: Self.artworkURL(detailed.artwork),
                curatorName: detailed.curatorName,
                descriptionText: detailed.standardDescription ?? detailed.shortDescription,
                appleMusicURL: detailed.url?.absoluteString,
                orderedTrackIDs: songs.map { $0.id.rawValue }
            ))
        }

        return ListeningFeaturedPlaylistsPayload(
            artistID: artistID,
            playlists: playlistPayloads,
            songs: Array(songPayloadsByID.values),
            fetchedAt: fetchedAt
        )
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

    private static func contentRatingRawValue(_ rating: ContentRating?) -> String? {
        switch rating {
        case .clean: "clean"
        case .explicit: "explicit"
        case nil: nil
        @unknown default: nil
        }
    }

    private static func audioVariantRawValue(_ variant: AudioVariant) -> String {
        switch variant {
        case .dolbyAtmos: "dolbyAtmos"
        case .dolbyAudio: "dolbyAudio"
        case .lossless: "lossless"
        case .highResolutionLossless: "highResolutionLossless"
        case .lossyStereo: "lossyStereo"
        case .spatialAudio: "spatialAudio"
        @unknown default: variant.description
        }
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
            topSongIDs
                + albums.flatMap { detail in detail.songs.map { $0.id.rawValue } }
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
