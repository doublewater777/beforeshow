import Foundation
@preconcurrency import MusicKit

/// Full-catalog playback on `ApplicationMusicPlayer`, the way Apple's MusicKit
/// samples drive it: one shared player, one queue per loaded disc, state read
/// straight from the player. Lock Screen and Control Center belong to the system.
@MainActor
final class MusicKitListeningPlaybackService: ListeningPlaybackServicing {
    let source = ListeningPlaybackSource.fullCatalog
    private let player: ApplicationMusicPlayer
    private var songsByID: [String: Song] = [:]
    private var durationBySongID: [String: TimeInterval] = [:]
    private(set) var queuedSongIDs: [String] = []

    init(player: ApplicationMusicPlayer = .shared) {
        self.player = player
    }

    var phase: ListeningPlaybackTransportPhase {
        switch player.state.playbackStatus {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        case .interrupted: .interrupted
        case .seekingForward, .seekingBackward: .seeking
        @unknown default: .stopped
        }
    }

    var currentSongID: String? {
        guard !queuedSongIDs.isEmpty else { return nil }
        // A finished queue has no current entry; its last song stays loaded.
        return currentEntrySongID ?? queuedSongIDs.last
    }

    var hasEnded: Bool {
        guard !queuedSongIDs.isEmpty else { return false }
        let status = player.state.playbackStatus
        guard status == .stopped || status == .paused else { return false }
        guard let songID = currentEntrySongID else { return true }
        return ListeningPlaybackCompletionPolicy.hasEnded(
            currentTime: currentTime,
            duration: duration(of: songID),
            isPlaying: false
        )
    }

    var failure: ListeningPlaybackError? { nil }

    var currentTime: TimeInterval {
        let time = player.playbackTime
        return time.isFinite ? max(0, time) : 0
    }

    var currentDuration: TimeInterval? {
        currentSongID.flatMap(duration(of:))
    }

    func prefetch(_ items: [ListeningPlaybackItem]) async {
        try? await fetchMissingSongs(items.map(\.songID))
    }

    func load(_ items: [ListeningPlaybackItem], startingAt songID: String?, at time: TimeInterval) async throws {
        guard !items.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        try await fetchMissingSongs(items.map(\.songID))
        // Songs the catalog no longer returns are skipped instead of failing the disc.
        let playable = items.filter { songsByID[$0.songID] != nil }
        guard let first = playable.first else {
            throw ListeningPlaybackError.songUnavailable(songID ?? items[0].songID)
        }
        for item in items {
            if let duration = item.duration { durationBySongID[item.songID] = duration }
        }
        let startID = Self.startingSongID(requested: songID, items: items, playable: playable) ?? first.songID
        let songs = playable.compactMap { songsByID[$0.songID] }
        queuedSongIDs = playable.map(\.songID)
        player.state.repeatMode = MusicPlayer.RepeatMode.none
        player.state.shuffleMode = .off
        player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: songsByID[startID])
        AppAudioSession.configureMusicPlayback()
        await AppAudioSession.waitForPendingOperations()
        try Task.checkCancellation()
        try await player.prepareToPlay()
        if time > 0 {
            player.playbackTime = time
        }
    }

    func play() async throws {
        AppAudioSession.configureMusicPlayback()
        await AppAudioSession.waitForPendingOperations()
        try Task.checkCancellation()
        try await player.play()
    }

    func pause() {
        player.pause()
    }

    func skipToNext() async throws {
        try await player.skipToNextEntry()
    }

    func skipToPrevious() async throws {
        try await player.skipToPreviousEntry()
    }

    func skip(to songID: String) async throws {
        guard queuedSongIDs.contains(songID), let song = songsByID[songID] else {
            throw ListeningPlaybackError.songUnavailable(songID)
        }
        let continuesPlaying = phase.isActive
        player.queue = ApplicationMusicPlayer.Queue(
            for: queuedSongIDs.compactMap { songsByID[$0] },
            startingAt: song
        )
        if continuesPlaying {
            try await play()
        }
    }

    func stop() {
        player.stop()
        queuedSongIDs = []
        AppAudioSession.releaseMusicPlayback()
    }

    private var currentEntrySongID: String? {
        guard case let .song(song) = player.queue.currentEntry?.item else { return nil }
        return song.id.rawValue
    }

    private func duration(of songID: String) -> TimeInterval? {
        songsByID[songID]?.duration ?? durationBySongID[songID]
    }

    /// The requested song, or the next one the catalog could resolve.
    private static func startingSongID(
        requested: String?,
        items: [ListeningPlaybackItem],
        playable: [ListeningPlaybackItem]
    ) -> String? {
        guard let requested,
              let index = items.firstIndex(where: { $0.songID == requested }) else { return nil }
        let playableIDs = Set(playable.map(\.songID))
        return items[index...].first { playableIDs.contains($0.songID) }?.songID
    }

    private func fetchMissingSongs(_ ids: [String]) async throws {
        var seen = Set<String>()
        let missing = ids.filter { songsByID[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty else { return }
        let batches = stride(from: 0, to: missing.count, by: 25).map {
            Array(missing[$0..<min($0 + 25, missing.count)])
        }
        let fetched = try await withThrowingTaskGroup(of: [Song].self) { group in
            for batch in batches {
                group.addTask {
                    var request = MusicCatalogResourceRequest<Song>(
                        matching: \.id,
                        memberOf: batch.map { MusicItemID($0) }
                    )
                    request.limit = batch.count
                    return Array(try await request.response().items)
                }
            }
            var songs: [Song] = []
            for try await batch in group { songs += batch }
            return songs
        }
        for song in fetched {
            songsByID[song.id.rawValue] = song
        }
    }
}
