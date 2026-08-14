import Foundation

#if canImport(MusicKit)
@preconcurrency import MusicKit
#endif

public struct ArtistWarmupArtistCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let artworkURL: URL?
    public let genreNames: [String]
    public let appleMusicURL: URL?

    public init(
        id: String,
        name: String,
        artworkURL: URL?,
        genreNames: [String] = [],
        appleMusicURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.genreNames = genreNames
        self.appleMusicURL = appleMusicURL
    }

    public var distinguishingDetail: String? {
        if let firstGenre = genreNames.first, !firstGenre.isEmpty {
            return firstGenre
        }
        return appleMusicURL?.host
    }
}

public struct ArtistWarmupPlaybackSnapshot: Equatable, Sendable {
    public let songID: String?
    public let currentTime: TimeInterval
    public let duration: TimeInterval?
    public let isPlaying: Bool

    public init(
        songID: String?,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool
    ) {
        self.songID = songID
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
    }
}

public struct ArtistWarmupArtistProfile: Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL?
    public let artworkURL: URL?
    public let editorialNotes: String?
    public let genreNames: [String]

    public init(
        id: String,
        name: String,
        url: URL?,
        artworkURL: URL?,
        editorialNotes: String?,
        genreNames: [String]
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.artworkURL = artworkURL
        self.editorialNotes = editorialNotes
        self.genreNames = genreNames
    }
}

public enum ArtistWarmupCatalogSource: Equatable, Sendable {
    case topSongs
    case album(String)
    case single(String)
    case compilationAlbum(String)
}

public struct ArtistWarmupCatalogSong: Equatable, Sendable {
    public let id: String
    public let artistID: String
    public let title: String
    public let albumTitle: String?
    public let artistName: String
    public let performerArtistIDs: [String]
    public let performerNames: [String]
    public let duration: TimeInterval?
    public let source: ArtistWarmupCatalogSource
    public let previewFallbackURL: URL?

    public init(
        id: String,
        artistID: String,
        title: String,
        albumTitle: String?,
        artistName: String,
        performerArtistIDs: [String],
        performerNames: [String],
        duration: TimeInterval?,
        source: ArtistWarmupCatalogSource,
        previewFallbackURL: URL?
    ) {
        self.id = id
        self.artistID = artistID
        self.title = title
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.performerArtistIDs = performerArtistIDs
        self.performerNames = performerNames
        self.duration = duration
        self.source = source
        self.previewFallbackURL = previewFallbackURL
    }
}

public enum ArtistWarmupCatalogCompleteness: Equatable, Sendable {
    case complete
    case partial(reason: String)
}

public struct ArtistWarmupCatalog: Equatable, Sendable {
    public let songs: [ArtistWarmupCatalogSong]
    public let completeness: ArtistWarmupCatalogCompleteness

    public init(songs: [ArtistWarmupCatalogSong], completeness: ArtistWarmupCatalogCompleteness) {
        self.songs = Self.dedupedByMusicItemID(songs)
        self.completeness = completeness
    }

    public var songIDsForFamiliarity: [String] {
        songs.map(\.id)
    }

    private static func dedupedByMusicItemID(_ songs: [ArtistWarmupCatalogSong]) -> [ArtistWarmupCatalogSong] {
        var seen = Set<String>()
        return songs.filter { song in
            seen.insert(song.id).inserted
        }
    }
}

public enum ArtistWarmupAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

public struct ArtistWarmupSubscriptionCapability: Equatable, Sendable {
    public let canPlayCatalogContent: Bool
    public let canBecomeSubscriber: Bool
    public let hasCloudLibraryEnabled: Bool

    public init(
        canPlayCatalogContent: Bool,
        canBecomeSubscriber: Bool,
        hasCloudLibraryEnabled: Bool
    ) {
        self.canPlayCatalogContent = canPlayCatalogContent
        self.canBecomeSubscriber = canBecomeSubscriber
        self.hasCloudLibraryEnabled = hasCloudLibraryEnabled
    }
}

public enum ArtistWarmupPlaybackScope: Equatable, Sendable {
    case allSongs
    case artist(String)

    fileprivate func includes(_ song: ArtistWarmupCatalogSong) -> Bool {
        switch self {
        case .allSongs:
            true
        case let .artist(artistID):
            song.artistID == artistID || song.performerArtistIDs.contains(artistID)
        }
    }
}

public enum ArtistWarmupMusicServiceError: Error, Equatable {
    case artistNotFound(String)
    case emptyQueue
    case musicKitUnavailable
}

public typealias ArtistWarmupCatalogResult = ArtistWarmupCatalog

@MainActor
public protocol ArtistWarmupCatalogProviding {
    func searchArtistCandidates(query: String, limit: Int) async throws -> [ArtistWarmupArtistCandidate]
    func fetchProviderArtistProfile(artistID: String) async throws -> ArtistWarmupArtistProfile
    func enumerateAudioCatalog(artistID: String) async -> ArtistWarmupCatalogResult
}

@MainActor
public protocol ArtistWarmupMusicCapabilityProviding {
    func authorizationStatus() async -> ArtistWarmupAuthorizationStatus
    func requestAuthorization() async -> ArtistWarmupAuthorizationStatus
    func subscriptionCapability() async throws -> ArtistWarmupSubscriptionCapability
    func subscriptionCapabilityUpdates() -> AsyncStream<ArtistWarmupSubscriptionCapability>
}

@MainActor
public protocol ArtistWarmupPlaying {
    func enqueue(_ songs: [ArtistWarmupCatalogSong], scopedTo scope: ArtistWarmupPlaybackScope) async throws
    func play() async throws
    func pause() async
    func skipToNextSong() async throws
    func skipToPreviousSong() async throws
    func playbackSnapshot() -> ArtistWarmupPlaybackSnapshot
}

@MainActor
public final class UnavailableArtistWarmupService:
    ArtistWarmupCatalogProviding,
    ArtistWarmupMusicCapabilityProviding,
    ArtistWarmupPlaying
{
    public init() {}

    public func searchArtistCandidates(query: String, limit: Int) async throws -> [ArtistWarmupArtistCandidate] {
        throw ArtistWarmupMusicServiceError.musicKitUnavailable
    }

    public func fetchProviderArtistProfile(artistID: String) async throws -> ArtistWarmupArtistProfile {
        throw ArtistWarmupMusicServiceError.musicKitUnavailable
    }

    public func enumerateAudioCatalog(artistID: String) async -> ArtistWarmupCatalogResult {
        ArtistWarmupCatalogResult(songs: [], completeness: .partial(reason: "music kit unavailable"))
    }

    public func authorizationStatus() async -> ArtistWarmupAuthorizationStatus {
        .restricted
    }

    public func requestAuthorization() async -> ArtistWarmupAuthorizationStatus {
        .restricted
    }

    public func subscriptionCapability() async throws -> ArtistWarmupSubscriptionCapability {
        ArtistWarmupSubscriptionCapability(
            canPlayCatalogContent: false,
            canBecomeSubscriber: false,
            hasCloudLibraryEnabled: false
        )
    }

    public func subscriptionCapabilityUpdates() -> AsyncStream<ArtistWarmupSubscriptionCapability> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func enqueue(
        _ songs: [ArtistWarmupCatalogSong],
        scopedTo scope: ArtistWarmupPlaybackScope
    ) async throws {
        throw ArtistWarmupMusicServiceError.musicKitUnavailable
    }

    public func play() async throws {
        throw ArtistWarmupMusicServiceError.musicKitUnavailable
    }

    public func pause() async {}

    public func skipToNextSong() async throws {
        throw ArtistWarmupMusicServiceError.musicKitUnavailable
    }

    public func skipToPreviousSong() async throws {
        throw ArtistWarmupMusicServiceError.musicKitUnavailable
    }

    public func playbackSnapshot() -> ArtistWarmupPlaybackSnapshot {
        ArtistWarmupPlaybackSnapshot(songID: nil, currentTime: 0, duration: nil, isPlaying: false)
    }
}

public enum FixtureArtistWarmupCatalog {
    case complete(songs: [ArtistWarmupCatalogSong])
    case partial(songs: [ArtistWarmupCatalogSong], reason: String)

    fileprivate var result: ArtistWarmupCatalogResult {
        switch self {
        case let .complete(songs):
            ArtistWarmupCatalogResult(songs: songs, completeness: .complete)
        case let .partial(songs, reason):
            ArtistWarmupCatalogResult(songs: songs, completeness: .partial(reason: reason))
        }
    }
}

public enum FixtureArtistWarmupPlaybackEvent: Equatable, Sendable {
    case enqueue([String])
    case play
    case pause
    case skipToNextSong
    case skipToPreviousSong
}

@MainActor
public final class FixtureArtistWarmupMusicService:
    ArtistWarmupCatalogProviding,
    ArtistWarmupMusicCapabilityProviding,
    ArtistWarmupPlaying
{
    private var candidates: [ArtistWarmupArtistCandidate]
    private var profiles: [String: ArtistWarmupArtistProfile]
    private var catalogs: [String: FixtureArtistWarmupCatalog]
    private var storedAuthorizationStatus: ArtistWarmupAuthorizationStatus
    private var storedSubscriptionCapability: ArtistWarmupSubscriptionCapability
    private var queue: [ArtistWarmupCatalogSong] = []
    private var isPlaying = false
    private var currentIndex = 0

    public private(set) var playbackEvents: [FixtureArtistWarmupPlaybackEvent] = []

    public init(
        candidates: [ArtistWarmupArtistCandidate] = [],
        profiles: [String: ArtistWarmupArtistProfile] = [:],
        catalogs: [String: FixtureArtistWarmupCatalog] = [:],
        authorizationStatus: ArtistWarmupAuthorizationStatus = .notDetermined,
        subscriptionCapability: ArtistWarmupSubscriptionCapability = ArtistWarmupSubscriptionCapability(
            canPlayCatalogContent: false,
            canBecomeSubscriber: false,
            hasCloudLibraryEnabled: false
        )
    ) {
        self.candidates = candidates
        self.profiles = profiles
        self.catalogs = catalogs
        self.storedAuthorizationStatus = authorizationStatus
        self.storedSubscriptionCapability = subscriptionCapability
    }

    public var enqueuedSongIDs: [String] {
        queue.map(\.id)
    }

    public func searchArtistCandidates(query: String, limit: Int) async throws -> [ArtistWarmupArtistCandidate] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = normalizedQuery.isEmpty
            ? candidates
            : candidates.filter { $0.name.lowercased().contains(normalizedQuery) }
        return Array(matches.prefix(max(0, limit)))
    }

    public func fetchProviderArtistProfile(artistID: String) async throws -> ArtistWarmupArtistProfile {
        guard let profile = profiles[artistID] else {
            throw ArtistWarmupMusicServiceError.artistNotFound(artistID)
        }
        return profile
    }

    public func enumerateAudioCatalog(artistID: String) async -> ArtistWarmupCatalogResult {
        catalogs[artistID]?.result ?? ArtistWarmupCatalogResult(
            songs: [],
            completeness: .partial(reason: "fixture catalog missing")
        )
    }

    public func authorizationStatus() async -> ArtistWarmupAuthorizationStatus {
        storedAuthorizationStatus
    }

    public func requestAuthorization() async -> ArtistWarmupAuthorizationStatus {
        storedAuthorizationStatus
    }

    public func subscriptionCapability() async throws -> ArtistWarmupSubscriptionCapability {
        storedSubscriptionCapability
    }

    public func subscriptionCapabilityUpdates() -> AsyncStream<ArtistWarmupSubscriptionCapability> {
        AsyncStream { continuation in
            continuation.yield(storedSubscriptionCapability)
            continuation.finish()
        }
    }

    public func enqueue(
        _ songs: [ArtistWarmupCatalogSong],
        scopedTo scope: ArtistWarmupPlaybackScope
    ) async throws {
        let scopedSongs = songs.filter { scope.includes($0) }
        guard !scopedSongs.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }
        queue = scopedSongs
        playbackEvents.append(.enqueue(scopedSongs.map(\.id)))
        currentIndex = 0
        isPlaying = false
    }

    public func play() async throws {
        guard !queue.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }
        isPlaying = true
        playbackEvents.append(.play)
    }

    public func pause() async {
        isPlaying = false
        playbackEvents.append(.pause)
    }

    public func skipToNextSong() async throws {
        guard !queue.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }
        currentIndex = min(queue.count - 1, currentIndex + 1)
        playbackEvents.append(.skipToNextSong)
    }

    public func skipToPreviousSong() async throws {
        guard !queue.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }
        currentIndex = max(0, currentIndex - 1)
        playbackEvents.append(.skipToPreviousSong)
    }

    public func playbackSnapshot() -> ArtistWarmupPlaybackSnapshot {
        ArtistWarmupPlaybackSnapshot(
            songID: queue.indices.contains(currentIndex) ? queue[currentIndex].id : nil,
            currentTime: 0,
            duration: queue.indices.contains(currentIndex) ? queue[currentIndex].duration : nil,
            isPlaying: isPlaying
        )
    }
}

#if canImport(MusicKit)
@MainActor
public final class MusicKitArtistWarmupService:
    ArtistWarmupCatalogProviding,
    ArtistWarmupMusicCapabilityProviding,
    ArtistWarmupPlaying
{
    private let player: ApplicationMusicPlayer
    private var enqueuedIDs: [String] = []

    public init(player: ApplicationMusicPlayer = .shared) {
        self.player = player
    }

    public func searchArtistCandidates(query: String, limit: Int) async throws -> [ArtistWarmupArtistCandidate] {
        var request = MusicCatalogSearchRequest(term: query, types: [Artist.self])
        request.limit = limit
        let response = try await request.response()
        return response.artists.map { artist in
            ArtistWarmupArtistCandidate(
                id: artist.id.rawValue,
                name: artist.name,
                artworkURL: artist.artwork?.url(width: 512, height: 512),
                genreNames: artist.genreNames ?? [],
                appleMusicURL: artist.url
            )
        }
    }

    public func fetchProviderArtistProfile(artistID: String) async throws -> ArtistWarmupArtistProfile {
        let artist = try await fetchArtist(artistID: artistID)
        return ArtistWarmupArtistProfile(
            id: artist.id.rawValue,
            name: artist.name,
            url: artist.url,
            artworkURL: artist.artwork?.url(width: 1200, height: 1200),
            editorialNotes: artist.editorialNotes?.standard ?? artist.editorialNotes?.short,
            genreNames: artist.genreNames ?? []
        )
    }

    public func enumerateAudioCatalog(artistID: String) async -> ArtistWarmupCatalogResult {
        do {
            let artist = try await fetchArtist(artistID: artistID)
            return await enumerateAudioCatalog(for: artist)
        } catch {
            return ArtistWarmupCatalogResult(
                songs: [],
                completeness: .partial(reason: "artist profile unavailable")
            )
        }
    }

    public func authorizationStatus() async -> ArtistWarmupAuthorizationStatus {
        Self.authorizationStatus(from: MusicAuthorization.currentStatus)
    }

    public func requestAuthorization() async -> ArtistWarmupAuthorizationStatus {
        await Self.authorizationStatus(from: MusicAuthorization.request())
    }

    public func subscriptionCapability() async throws -> ArtistWarmupSubscriptionCapability {
        Self.capability(from: try await MusicSubscription.current)
    }

    public func subscriptionCapabilityUpdates() -> AsyncStream<ArtistWarmupSubscriptionCapability> {
        AsyncStream { continuation in
            let task = Task {
                for await subscription in MusicSubscription.subscriptionUpdates {
                    continuation.yield(Self.capability(from: subscription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func enqueue(
        _ songs: [ArtistWarmupCatalogSong],
        scopedTo scope: ArtistWarmupPlaybackScope
    ) async throws {
        let scopedIDs = songs.filter { scope.includes($0) }.map(\.id)
        guard !scopedIDs.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }

        let playableSongs = try await fetchSongs(songIDs: scopedIDs)
        guard !playableSongs.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }

        player.queue = ApplicationMusicPlayer.Queue(for: playableSongs)
        enqueuedIDs = playableSongs.map { $0.id.rawValue }
    }

    public func play() async throws {
        guard !enqueuedIDs.isEmpty else {
            throw ArtistWarmupMusicServiceError.emptyQueue
        }
        try await player.play()
    }

    public func pause() async {
        player.pause()
    }

    public func skipToNextSong() async throws {
        try await player.skipToNextEntry()
    }

    public func skipToPreviousSong() async throws {
        try await player.skipToPreviousEntry()
    }

    public func playbackSnapshot() -> ArtistWarmupPlaybackSnapshot {
        let currentItem = player.queue.currentEntry?.item
        let song: Song?
        if case let .song(currentSong) = currentItem {
            song = currentSong
        } else {
            song = nil
        }

        return ArtistWarmupPlaybackSnapshot(
            songID: song?.id.rawValue ?? enqueuedIDs.first,
            currentTime: player.playbackTime,
            duration: song?.duration,
            isPlaying: player.state.playbackStatus == .playing
        )
    }

    private func fetchArtist(artistID: String) async throws -> Artist {
        var request = MusicCatalogResourceRequest<Artist>(
            matching: \.id,
            equalTo: MusicItemID(rawValue: artistID)
        )
        request.properties = [.topSongs, .albums, .singles, .compilationAlbums]
        let response = try await request.response()
        guard let artist = response.items.first else {
            throw ArtistWarmupMusicServiceError.artistNotFound(artistID)
        }
        return artist
    }

    private func enumerateAudioCatalog(for artist: Artist) async -> ArtistWarmupCatalogResult {
        var songs: [ArtistWarmupCatalogSong] = []
        var partialReasons: [String] = []

        await appendSongs(
            artist.topSongs,
            artistID: artist.id.rawValue,
            source: .topSongs,
            to: &songs,
            partialReasons: &partialReasons,
            reason: "top songs unavailable"
        )

        await appendAlbumSongs(
            artist.albums,
            artistID: artist.id.rawValue,
            source: { .album($0) },
            to: &songs,
            partialReasons: &partialReasons,
            reason: "album tracks unavailable"
        )
        await appendAlbumSongs(
            artist.singles,
            artistID: artist.id.rawValue,
            source: { .single($0) },
            to: &songs,
            partialReasons: &partialReasons,
            reason: "single tracks unavailable"
        )
        await appendAlbumSongs(
            artist.compilationAlbums,
            artistID: artist.id.rawValue,
            source: { .compilationAlbum($0) },
            to: &songs,
            partialReasons: &partialReasons,
            reason: "compilation album tracks unavailable"
        )

        return ArtistWarmupCatalogResult(
            songs: songs,
            completeness: partialReasons.isEmpty ? .complete : .partial(reason: partialReasons.joined(separator: "; "))
        )
    }

    private func appendSongs(
        _ collection: MusicItemCollection<Song>?,
        artistID: String,
        source: ArtistWarmupCatalogSource,
        to songs: inout [ArtistWarmupCatalogSong],
        partialReasons: inout [String],
        reason: String
    ) async {
        guard var collection else {
            return
        }

        do {
            repeat {
                for song in collection {
                    songs.append(await Self.catalogSong(from: song, artistID: artistID, source: source))
                }
                guard collection.hasNextBatch, let next = try await collection.nextBatch() else {
                    break
                }
                collection = next
            } while true
        } catch {
            partialReasons.append(reason)
        }
    }

    private func appendAlbumSongs(
        _ albums: MusicItemCollection<Album>?,
        artistID: String,
        source: (String) -> ArtistWarmupCatalogSource,
        to songs: inout [ArtistWarmupCatalogSong],
        partialReasons: inout [String],
        reason: String
    ) async {
        guard var albums else {
            return
        }

        do {
            repeat {
                for album in albums {
                    let hydratedAlbum = try await album.with(.tracks)
                    guard var tracks = hydratedAlbum.tracks else {
                        continue
                    }
                    repeat {
                        for track in tracks {
                            if case let .song(song) = track {
                                songs.append(await Self.catalogSong(
                                    from: song,
                                    artistID: artistID,
                                    source: source(album.id.rawValue)
                                ))
                            }
                        }
                        guard tracks.hasNextBatch, let nextTracks = try await tracks.nextBatch() else {
                            break
                        }
                        tracks = nextTracks
                    } while true
                }

                guard albums.hasNextBatch, let nextAlbums = try await albums.nextBatch() else {
                    break
                }
                albums = nextAlbums
            } while true
        } catch {
            partialReasons.append(reason)
        }
    }

    private func fetchSongs(songIDs: [String]) async throws -> [Song] {
        var request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            memberOf: songIDs.map { MusicItemID(rawValue: $0) }
        )
        request.properties = [.artists]
        let response = try await request.response()
        let order = Dictionary(uniqueKeysWithValues: songIDs.enumerated().map { ($0.element, $0.offset) })
        return response.items.sorted {
            (order[$0.id.rawValue] ?? Int.max) < (order[$1.id.rawValue] ?? Int.max)
        }
    }

    private static func catalogSong(
        from song: Song,
        artistID: String,
        source: ArtistWarmupCatalogSource
    ) async -> ArtistWarmupCatalogSong {
        let hydratedSong = (try? await song.with(.artists)) ?? song
        let performers = hydratedSong.artists?.map { artist in
            ArtistWarmupArtistCandidate(
                id: artist.id.rawValue,
                name: artist.name,
                artworkURL: artist.artwork?.url(width: 512, height: 512)
            )
        } ?? []

        return ArtistWarmupCatalogSong(
            id: song.id.rawValue,
            artistID: artistID,
            title: song.title,
            albumTitle: song.albumTitle,
            artistName: song.artistName,
            performerArtistIDs: performers.map(\.id),
            performerNames: performers.map(\.name),
            duration: song.duration,
            source: source,
            previewFallbackURL: song.previewAssets?.first?.url
        )
    }

    private static func authorizationStatus(
        from status: MusicAuthorization.Status
    ) -> ArtistWarmupAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorized:
            .authorized
        @unknown default:
            .restricted
        }
    }

    private static func capability(from subscription: MusicSubscription) -> ArtistWarmupSubscriptionCapability {
        ArtistWarmupSubscriptionCapability(
            canPlayCatalogContent: subscription.canPlayCatalogContent,
            canBecomeSubscriber: subscription.canBecomeSubscriber,
            hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled
        )
    }
}
#endif
