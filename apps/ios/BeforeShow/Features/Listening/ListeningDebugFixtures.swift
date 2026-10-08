#if DEBUG
import Foundation
import SwiftData

enum ListeningFixtureScenario: String, CaseIterable {
    case artistLibrary = "artist-library", artistSearchFailure = "artist-search-failure"
    case noCurrent = "no-current", singleFull = "single-full", multiFull = "multi-full"
    case festival = "festival", fifteen = "fifteen", manyDiscs = "many-discs", emptyAlbums = "empty-albums"
    case previewOnly = "preview-only", metadataOnly = "metadata-only", cachedError = "cached-error", endedCurrent = "ended-current"
    case coldLoading = "cold-loading", authorizationFlow = "authorization-flow"
    case coldProgressive = "cold-progressive"
    case authorizationDenied = "authorization-denied", catalogFailure = "catalog-failure"
    var startsWithoutCatalog: Bool {
        [.coldLoading, .coldProgressive, .authorizationFlow, .authorizationDenied, .catalogFailure].contains(self)
    }
    static var requested: Self? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--listen-fixture"), args.indices.contains(index + 1) { return Self(rawValue: args[index + 1]) }
        return args.contains("--listening-fixture") ? .metadataOnly : nil
    }
}

@MainActor struct ListeningDebugFixtures {
    let scenario: ListeningFixtureScenario
    let container: ModelContainer

    /// A disc with real cover art, loaded by `--listen-seed-disc <url>` so
    /// artwork-driven disc details can be inspected in the simulator.
    var seededDisc: ListeningDisc? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--listen-seed-disc"),
              args.indices.contains(index + 1),
              let url = URL(string: args[index + 1]) else { return nil }
        let tracks = (0..<4).map { number in
            ListeningDiscTrack(CatalogSong(
                appleMusicSongID: "seed-song-" + String(number),
                title: ["夜色", "最后一班车", "微光", "蓝色时刻"][number],
                artistName: "夜航",
                albumID: "seed-album",
                duration: 180,
                performerArtistIDs: ["seed-artist"]
            ))
        }
        return ListeningDisc(id: "seed-album", title: "夜航 · Album", artworkURL: url, tracks: tracks)
    }

    /// A compilation disc whose tracks carry the `--listen-seed-mosaic` covers,
    /// seated and revealed by `--listen-seed-disc-seat` for simulator previews.
    var mosaicSeededDisc: ListeningDisc? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--listen-seed-mosaic"),
              args.indices.contains(index + 1) else { return nil }
        let urls = args[index + 1].split(separator: ",").map(String.init)
        guard !urls.isEmpty else { return nil }
        let tracks = (0..<4).map { number in
            var song = CatalogSong(
                appleMusicSongID: "seed-song-" + String(number),
                title: ["夜色", "最后一班车", "微光", "蓝色时刻"][number],
                artistName: "夜航",
                albumID: "seed-album",
                duration: 180,
                performerArtistIDs: ["seed-artist"]
            )
            song.artworkURL = urls[number % urls.count]
            return ListeningDiscTrack(song)
        }
        return ListeningDisc(
            id: "seed-compilation",
            title: "现场预习 01",
            artworkURL: nil,
            tracks: tracks,
            origin: .compilation(showID: UUID(), number: 1)
        )
    }

    /// Covers for the compilation mosaic, loaded by `--listen-seed-mosaic`
    /// with up to four comma-separated image URLs written onto the fixture
    /// catalog's songs and album.
    private func applyMosaicCovers(to context: ModelContext) throws {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--listen-seed-mosaic"),
              args.indices.contains(index + 1) else { return }
        let urls = args[index + 1].split(separator: ",").map(String.init)
        guard !urls.isEmpty else { return }
        let songIDs = (0..<4).map { "fixture-song-0-" + String($0) }
        for (offset, id) in songIDs.enumerated() {
            let predicate = #Predicate<CatalogSong> { $0.appleMusicSongID == id }
            if let song = try context.fetch(FetchDescriptor<CatalogSong>(predicate: predicate)).first {
                song.artworkURL = urls[offset % urls.count]
            }
        }
        let albumPredicate = #Predicate<CatalogAlbum> { $0.appleMusicAlbumID == "fixture-album-0" }
        if let album = try context.fetch(FetchDescriptor<CatalogAlbum>(predicate: albumPredicate)).first {
            album.artworkURL = urls[0]
        }
        try context.save()
    }

    init(scenario: ListeningFixtureScenario) throws {
        self.scenario = scenario
        container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        guard scenario != .noCurrent else { return }
        let context = container.mainContext
        let start = Date().addingTimeInterval(scenario == .endedCurrent ? -86400 : 864000)
        let show = try Show(name: "夜航 · Listen", date: start, startTime: start)
        if scenario == .endedCurrent { show.endedAt = start.addingTimeInterval(7200) }
        let seedArgs = ProcessInfo.processInfo.arguments
        if let seedIndex = seedArgs.firstIndex(of: "--listen-seed-disc"),
           seedArgs.indices.contains(seedIndex + 1) {
            show.coverImageURL = seedArgs[seedIndex + 1]
        }
        let names = ["Aimer", "YOASOBI", "宇多田ヒカル", "RADWIMPS", "米津玄師", "椎名林檎", "King Gnu", "藤井風", "Official髭男dism", "Vaundy", "あいみょん", "Mrs. GREEN APPLE", "ずっと真夜中でいいのに。", "羊文学", "ヨルシカ"]
        let count = scenario == .fifteen || scenario == .manyDiscs ? 15 : scenario == .festival ? 8 : scenario == .multiFull || scenario == .coldProgressive ? 2 : 1
        let artistNames = scenario == .multiFull ? ["夜航", "海岸"] : Array(names.prefix(count))
        show.artists = artistNames.enumerated().map { index, name in
            ArtistSlot(name: name, avatarURL: nil, appleMusicArtistID: scenario == .multiFull ? nil : "fixture-artist-\(index)")
        }
        context.insert(show)
        context.insert(CurrentShowSelection(selectedShowID: show.id))
        for index in artistNames.indices where !scenario.startsWithoutCatalog {
            let artistID = "fixture-artist-\(index)"
            let songIDs = (0..<4).map { "fixture-song-\(index)-\($0)" }
            for (number, id) in songIDs.enumerated() {
                context.insert(CatalogSong(appleMusicSongID: id, title: ["夜色", "最后一班车", "微光", "蓝色时刻"][number],
                    artistName: artistNames[index], albumID: "fixture-album-\(index)", duration: scenario == .manyDiscs ? 1000 : 180,
                    performerArtistIDs: [artistID], previewURL: scenario == .previewOnly ? "https://example.invalid/preview.m4a" : nil))
            }
            context.insert(CatalogAlbum(appleMusicAlbumID: "fixture-album-\(index)", title: "\(artistNames[index]) · Album", artistIDs: [artistID], artistNames: [artistNames[index]], orderedTrackIDs: songIDs))
            context.insert(ArtistCatalogSnapshot(artistID: artistID, artistName: artistNames[index],
                orderedSongIDs: songIDs, topSongIDs: Array(songIDs.prefix(2)), albumIDs: scenario == .emptyAlbums ? [] : ["fixture-album-\(index)"]))
        }
        if scenario == .artistLibrary {
            let albumIDs = (1...4).map { "fixture-library-\($0)" }
            for (index, id) in albumIDs.enumerated() {
                context.insert(CatalogAlbum(appleMusicAlbumID: id, title: "Aimer · Album \(index + 1)",
                    artistIDs: ["fixture-artist-0"], artistNames: ["Aimer"],
                    orderedTrackIDs: (0..<4).map { "fixture-song-0-\($0)" }))
            }
            let predicate = #Predicate<ArtistCatalogSnapshot> { $0.artistID == "fixture-artist-0" }
            if let snapshot = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                snapshot.albumIDs = albumIDs
            }
        }
        if scenario == .endedCurrent {
            context.insert(ShowWantsLiveSong(showID: show.id, songID: "fixture-song-0-0", createdAt: start.addingTimeInterval(-100)))
        }
        try context.save()
        try applyMosaicCovers(to: context)
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
    }
}

struct ListeningFixtureArtistSearch: ArtistSearchServicing {
    var fails = false
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        if fails { throw URLError(.notConnectedToInternet) }
        guard let index = ["夜航", "海岸"].firstIndex(of: query) else { return [] }
        return [RecognizedArtist(id: "fixture-artist-\(index)", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
    }
}

final class ListeningFixtureCatalog: ListeningMusicCatalogServicing, @unchecked Sendable {
    let scenario: ListeningFixtureScenario
    private let lock = NSLock()
    private var authorization: ListeningMusicAuthorizationStatus

    /// Scales the simulated network delays; tests pass a small value.
    let pace: Double

    init(scenario: ListeningFixtureScenario, pace: Double = 1) {
        self.scenario = scenario
        self.pace = pace
        authorization = scenario == .authorizationFlow ? .notDetermined : scenario == .authorizationDenied ? .denied : .authorized
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { lock.withLock { authorization } }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        if scenario == .authorizationFlow {
            try? await Task.sleep(for: .seconds(3) * pace)
            lock.withLock { authorization = .authorized }
        }
        return currentAuthorizationStatus()
    }
    func currentAccess() async -> ListeningMusicAccess {
        if scenario == .coldProgressive { NSLog("ListeningColdStart access %.3f", ProcessInfo.processInfo.systemUptime) }
        if scenario == .coldLoading { try? await Task.sleep(for: .seconds(3) * pace) }
        let status = currentAuthorizationStatus()
        return .init(authorizationStatus: status, canPlayCatalogContent: status == .authorized && scenario != .previewOnly && scenario != .metadataOnly)
    }
    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        if scenario == .coldProgressive {
            // One slow artist must not hold the other artist's playable CD hostage.
            NSLog("ListeningColdStart request %@ %.3f", artistID, ProcessInfo.processInfo.systemUptime)
            try await Task.sleep(for: (artistID.hasSuffix("0") ? .seconds(15) : .milliseconds(250)) * pace)
            NSLog("ListeningColdStart result %@ %.3f", artistID, ProcessInfo.processInfo.systemUptime)
            let name = artistID.hasSuffix("0") ? "Aimer" : "YOASOBI"
            return [.init(songID: "fixture-song-\(artistID.hasSuffix("0") ? 0 : 1)-0", title: "夜色", artistName: name,
                          albumID: nil, albumTitle: nil, artworkURL: nil, duration: 180,
                          performerArtistIDs: [artistID], performerArtistNames: [name], previewURL: nil)]
        }

        guard scenario.startsWithoutCatalog,
              currentAuthorizationStatus() == .authorized else {
            return []
        }

        let artistIndex = artistID.hasSuffix("1") ? 1 : 0
        let artistName = artistIndex == 1 ? "YOASOBI" : "Aimer"
        return (0..<2).map { number in
            .init(
                songID: "fixture-song-\(artistIndex)-\(number)",
                title: ["夜色", "最后一班车"][number],
                artistName: artistName,
                albumID: nil,
                albumTitle: nil,
                artworkURL: nil,
                duration: 180,
                performerArtistIDs: [artistID],
                performerArtistNames: [artistName],
                previewURL: nil
            )
        }
    }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        if scenario.startsWithoutCatalog { try await Task.sleep(for: .seconds(3) * pace) }
        if scenario == .cachedError || scenario == .catalogFailure { throw ListeningCatalogError.incompleteCatalog(artistID) }
        let ids = (0..<4).map { "fixture-song-\(artistID.hasSuffix("1") ? 1 : 0)-\($0)" }
        let songs: [ListeningCatalogSongPayload] = scenario.startsWithoutCatalog ? ids.map {
            .init(songID: $0, title: "夜色", artistName: "Aimer", albumID: nil, albumTitle: nil,
                  artworkURL: nil, duration: 180, performerArtistIDs: [artistID], performerArtistNames: ["Aimer"], previewURL: nil)
        } : []
        // Same snapshot metadata, explicit mock transport. No network or audio.
        return .init(artistID: artistID, artistName: artistID.hasSuffix("1") ? "海岸" : "夜航", artworkURL: nil,
                     editorialText: nil, genreNames: [], orderedSongIDs: ids, topSongIDs: Array(ids.prefix(2)),
                     albumIDs: scenario == .artistLibrary ? (1...4).map { "fixture-library-\($0)" }
                        : scenario.startsWithoutCatalog ? [] : ["fixture-album-\(artistID.hasSuffix("1") ? 1 : 0)"], songs: songs, albums: [], fetchedAt: fetchedAt)
    }
}

/// Simulated player for fixtures: no network or audio, time follows the clock.
@MainActor @Observable final class ListeningFixturePlayer: ListeningPlaybackServicing {
    let source: ListeningPlaybackSource
    private(set) var phase: ListeningPlaybackTransportPhase = .stopped
    private(set) var currentSongID: String?
    private(set) var queuedSongIDs: [String] = []
    @ObservationIgnored private var items: [ListeningPlaybackItem] = []
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var elapsed: TimeInterval = 0

    init(source: ListeningPlaybackSource = .fullCatalog) {
        self.source = source
    }

    var hasEnded: Bool { false }
    var failure: ListeningPlaybackError? { nil }

    var currentDuration: TimeInterval? {
        guard let item = items.first(where: { $0.songID == currentSongID }) else { return nil }
        return source == .preview ? 30 : item.duration ?? 180
    }

    var currentTime: TimeInterval {
        let value = elapsed + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
        return min(value, currentDuration ?? value)
    }

    func load(_ items: [ListeningPlaybackItem], startingAt songID: String?, at time: TimeInterval) async throws {
        let playable = source == .preview ? items.filter { $0.previewURL != nil } : items
        guard let first = playable.first else { throw ListeningPlaybackError.emptyQueue }
        self.items = playable
        queuedSongIDs = playable.map(\.songID)
        currentSongID = playable.first { $0.songID == songID }?.songID ?? first.songID
        elapsed = time
        startedAt = nil
        phase = .paused
    }

    func play() async throws {
        guard currentSongID != nil else { throw ListeningPlaybackError.emptyQueue }
        if startedAt == nil { startedAt = Date() }
        phase = .playing
    }

    func pause() {
        if let startedAt { elapsed += Date().timeIntervalSince(startedAt) }
        startedAt = nil
        if currentSongID != nil { phase = .paused }
    }

    func skipToNext() async throws { try move(by: 1) }
    func skipToPrevious() async throws { try move(by: -1) }

    func skip(to songID: String) async throws {
        guard queuedSongIDs.contains(songID) else { throw ListeningPlaybackError.songUnavailable(songID) }
        currentSongID = songID
        restartClock()
    }

    func stop() {
        items = []
        queuedSongIDs = []
        currentSongID = nil
        startedAt = nil
        elapsed = 0
        phase = .stopped
    }

    private func move(by delta: Int) throws {
        guard let currentSongID,
              let index = queuedSongIDs.firstIndex(of: currentSongID),
              queuedSongIDs.indices.contains(index + delta) else {
            throw ListeningPlaybackError.queueBoundary
        }
        self.currentSongID = queuedSongIDs[index + delta]
        restartClock()
    }

    private func restartClock() {
        elapsed = 0
        if startedAt != nil { startedAt = Date() }
    }
}
#endif
