#if DEBUG
import Foundation
import SwiftData

enum ListeningFixtureScenario: String, CaseIterable {
    case noCurrent = "no-current", singleFull = "single-full", multiFull = "multi-full"
    case previewOnly = "preview-only", metadataOnly = "metadata-only", cachedError = "cached-error", endedCurrent = "ended-current"
    static var requested: Self? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--listen-fixture"), args.indices.contains(index + 1) { return Self(rawValue: args[index + 1]) }
        return args.contains("--listening-fixture") ? .metadataOnly : nil
    }
}

@MainActor struct ListeningDebugFixtures {
    let scenario: ListeningFixtureScenario
    let container: ModelContainer
    init(scenario: ListeningFixtureScenario) throws {
        self.scenario = scenario
        container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        guard scenario != .noCurrent else { return }
        let context = container.mainContext
        let start = Date().addingTimeInterval(scenario == .endedCurrent ? -86400 : 864000)
        let show = try Show(name: "夜航 · Listen", date: start, startTime: start)
        if scenario == .endedCurrent { show.endedAt = start.addingTimeInterval(7200) }
        let artistNames = scenario == .multiFull ? ["夜航", "海岸"] : ["夜航"]
        show.artists = artistNames.enumerated().map { index, name in
            ArtistSlot(name: name, avatarURL: nil, appleMusicArtistID: scenario == .multiFull ? nil : "fixture-artist-\(index)")
        }
        context.insert(show)
        context.insert(CurrentShowSelection(selectedShowID: show.id))
        for index in 0..<(scenario == .multiFull ? 2 : 1) {
            let artistID = "fixture-artist-\(index)"
            let songIDs = (0..<4).map { "fixture-song-\(index)-\($0)" }
            for (number, id) in songIDs.enumerated() {
                context.insert(CatalogSong(appleMusicSongID: id, title: ["夜色", "最后一班车", "微光", "蓝色时刻"][number],
                    artistName: artistNames[index], albumID: "fixture-album-\(index)", duration: 180,
                    performerArtistIDs: [artistID], previewURL: scenario == .previewOnly ? "https://example.invalid/preview.m4a" : nil))
            }
            context.insert(CatalogAlbum(appleMusicAlbumID: "fixture-album-\(index)", title: "夜航 \(index + 1)", artistIDs: [artistID], orderedTrackIDs: songIDs))
            context.insert(ArtistCatalogSnapshot(artistID: artistID, artistName: artistNames[index],
                orderedSongIDs: songIDs, topSongIDs: Array(songIDs.prefix(2)), albumIDs: ["fixture-album-\(index)"]))
        }
        if scenario == .endedCurrent {
            context.insert(ShowWantsLiveSong(showID: show.id, songID: "fixture-song-0-0", createdAt: start.addingTimeInterval(-100)))
        }
        try context.save()
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
    }
}

struct ListeningFixtureArtistSearch: ArtistSearchServicing {
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        guard let index = ["夜航", "海岸"].firstIndex(of: query) else { return [] }
        return [RecognizedArtist(id: "fixture-artist-\(index)", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
    }
}

struct ListeningFixtureCatalog: ListeningMusicCatalogServicing {
    let scenario: ListeningFixtureScenario
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .authorized, canPlayCatalogContent: scenario != .previewOnly && scenario != .metadataOnly)
    }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        if scenario == .cachedError { throw ListeningCatalogError.incompleteCatalog(artistID) }
        let ids = (0..<4).map { "fixture-song-\(artistID.hasSuffix("1") ? 1 : 0)-\($0)" }
        // Same snapshot metadata, explicit mock transport. No network or audio.
        return .init(artistID: artistID, artistName: artistID.hasSuffix("1") ? "海岸" : "夜航", artworkURL: nil,
                     editorialText: nil, genreNames: [], orderedSongIDs: ids, topSongIDs: Array(ids.prefix(2)),
                     albumIDs: ["fixture-album-\(artistID.hasSuffix("1") ? 1 : 0)"], songs: [], albums: [], fetchedAt: fetchedAt)
    }
}

@MainActor final class ListeningFixturePlayer: ListeningPlaybackServicing {
    var item: ListeningPlaybackItem?
    var source: ListeningPlaybackSource = .fullCatalog
    var start: Date?
    var elapsed: TimeInterval = 0
    func prepare(items: [ListeningPlaybackItem], source: ListeningPlaybackSource, startingAtSongID: String?) async throws {
        self.source = source; item = items.first; elapsed = 0; start = nil
    }
    func play() async throws { start = Date() }
    func pause() { if let start { elapsed += Date().timeIntervalSince(start) }; start = nil }
    func seek(to time: TimeInterval) { elapsed = time; if start != nil { start = Date() } }
    func skipToNext() async throws { throw ListeningPlaybackError.queueBoundary }
    func skipToPrevious() async throws { throw ListeningPlaybackError.queueBoundary }
    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard let item else { return nil }
        let duration = source == .preview ? 30 : (item.duration ?? 180)
        let value = elapsed + (start.map { observedAt.timeIntervalSince($0) } ?? 0)
        return .init(songID: item.songID, source: source, currentTime: min(value, duration), duration: duration,
                     isPlaying: start != nil && value < duration, observedAt: observedAt, hasEnded: value >= duration)
    }
    func stop() { item = nil; start = nil; elapsed = 0 }
}
#endif
