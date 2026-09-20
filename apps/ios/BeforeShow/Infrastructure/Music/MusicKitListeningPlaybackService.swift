import Foundation
import Observation
@preconcurrency import MusicKit

@MainActor
final class MusicKitListeningPlaybackService: ListeningPlaybackServicing {
    private let player: ApplicationMusicPlayer
    private var durationBySongID: [String: TimeInterval] = [:]

    init(player: ApplicationMusicPlayer = .shared) {
        self.player = player
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        guard source == .fullCatalog else {
            throw ListeningPlaybackError.unsupportedSource
        }
        guard !items.isEmpty else {
            throw ListeningPlaybackError.emptyQueue
        }
        if let startingAtSongID,
           !items.contains(where: { $0.songID == startingAtSongID }) {
            throw ListeningPlaybackError.songUnavailable(startingAtSongID)
        }

        let songs = try await fetchSongs(ids: items.map(\.songID))
        guard songs.count == items.count else {
            let fetchedIDs = Set(songs.map { $0.id.rawValue })
            let missingID = items.first { !fetchedIDs.contains($0.songID) }?.songID ?? items[0].songID
            throw ListeningPlaybackError.songUnavailable(missingID)
        }

        let orderedByID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id.rawValue, $0) })
        let orderedSongs = items.compactMap { orderedByID[$0.songID] }
        let startingSong = startingAtSongID.flatMap { orderedByID[$0] }
        durationBySongID = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.duration.map { (item.songID, $0) }
        })
        player.state.repeatMode = MusicPlayer.RepeatMode.none
        player.state.shuffleMode = .off
        player.queue = ApplicationMusicPlayer.Queue(for: orderedSongs, startingAt: startingSong)
        try await player.prepareToPlay()
    }

    func play() async throws {
        AppAudioSession.configureMusicPlayback()
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

    func seek(to time: TimeInterval) {
        player.playbackTime = max(0, time)
    }

    func transportEvents() -> AsyncStream<ListeningPlaybackSample> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                let observations = Observations {
                    MusicKitTransportObservation(
                        status: self.player.state.playbackStatus,
                        songID: self.currentSongID
                    )
                }

                for await _ in observations {
                    if Task.isCancelled { break }
                    if let sample = self.snapshot(observedAt: Date()) {
                        continuation.yield(sample)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func snapshot(observedAt: Date = Date()) -> ListeningPlaybackSample? {
        guard case let .song(song) = player.queue.currentEntry?.item else {
            return nil
        }
        let currentTime = max(0, player.playbackTime)
        let duration = song.duration ?? durationBySongID[song.id.rawValue]
        let phase = transportPhase(for: player.state.playbackStatus)
        return ListeningPlaybackSample(
            songID: song.id.rawValue,
            source: .fullCatalog,
            currentTime: currentTime,
            duration: duration,
            phase: phase,
            observedAt: observedAt,
            hasEnded: ListeningPlaybackCompletionPolicy.hasEnded(
                currentTime: currentTime,
                duration: duration,
                isPlaying: phase.isPlaying
            )
        )
    }

    func stop() {
        player.stop()
        durationBySongID = [:]
        AppAudioSession.releaseMusicPlayback()
    }

    private var currentSongID: String? {
        guard case let .song(song) = player.queue.currentEntry?.item else { return nil }
        return song.id.rawValue
    }

    private func transportPhase(
        for status: MusicPlayer.PlaybackStatus
    ) -> ListeningPlaybackTransportPhase {
        switch status {
        case .playing:
            .playing
        case .paused:
            .paused
        case .stopped:
            .stopped
        case .interrupted:
            .interrupted
        case .seekingForward, .seekingBackward:
            .seeking
        @unknown default:
            .stopped
        }
    }

    private func fetchSongs(ids: [String]) async throws -> [Song] {
        var fetched: [Song] = []
        for start in stride(from: 0, to: ids.count, by: 25) {
            let batch = Array(ids[start..<min(start + 25, ids.count)])
            var request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                memberOf: batch.map { MusicItemID($0) }
            )
            request.limit = batch.count
            let response = try await request.response()
            fetched.append(contentsOf: response.items)
        }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return fetched.sorted {
            (order[$0.id.rawValue] ?? Int.max) < (order[$1.id.rawValue] ?? Int.max)
        }
    }
}

private struct MusicKitTransportObservation: Equatable {
    let status: MusicPlayer.PlaybackStatus
    let songID: String?
}
