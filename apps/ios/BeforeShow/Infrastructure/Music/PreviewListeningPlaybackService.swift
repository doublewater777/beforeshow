import AVFoundation
import Foundation

@MainActor
final class PreviewListeningPlaybackService: ListeningPlaybackServicing {
    private let player: AVPlayer
    private var queue: [ListeningPlaybackItem] = []
    private var currentIndex = 0

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        guard source == .preview else {
            throw ListeningPlaybackError.unsupportedSource
        }
        let playableItems = items.filter { $0.previewURL != nil }
        guard !playableItems.isEmpty else {
            throw ListeningPlaybackError.emptyQueue
        }
        if let startingAtSongID,
           !playableItems.contains(where: { $0.songID == startingAtSongID }) {
            throw ListeningPlaybackError.songUnavailable(startingAtSongID)
        }
        queue = playableItems
        if let startingAtSongID,
           let index = queue.firstIndex(where: { $0.songID == startingAtSongID }) {
            currentIndex = index
        } else {
            currentIndex = 0
        }
        replaceCurrentItem()
    }

    func play() async throws {
        guard player.currentItem != nil else {
            throw ListeningPlaybackError.emptyQueue
        }
        AppAudioSession.configureMusicPlayback()
        player.play()
    }

    func pause() {
        player.pause()
    }

    func skipToNext() async throws {
        guard !queue.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        guard currentIndex + 1 < queue.count else { throw ListeningPlaybackError.queueBoundary }
        let shouldResume = player.timeControlStatus == .playing
        currentIndex += 1
        replaceCurrentItem()
        if shouldResume { player.play() }
    }

    func skipToPrevious() async throws {
        guard !queue.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        guard currentIndex > 0 else { throw ListeningPlaybackError.queueBoundary }
        let shouldResume = player.timeControlStatus == .playing
        currentIndex -= 1
        replaceCurrentItem()
        if shouldResume { player.play() }
    }

    func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

    func snapshot(observedAt: Date = Date()) -> ListeningPlaybackSample? {
        guard queue.indices.contains(currentIndex) else { return nil }
        let item = queue[currentIndex]
        let currentTime = max(0, player.currentTime().seconds.finiteValue ?? 0)
        let playerDuration = player.currentItem?.duration.seconds.positiveFiniteValue
        let duration = playerDuration ?? item.duration
        let isPlaying = player.timeControlStatus == .playing
        return ListeningPlaybackSample(
            songID: item.songID,
            source: .preview,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            observedAt: observedAt,
            hasEnded: ListeningPlaybackCompletionPolicy.hasEnded(
                currentTime: currentTime,
                duration: duration,
                isPlaying: isPlaying
            )
        )
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        currentIndex = 0
        AppAudioSession.configureAmbient()
    }

    private func replaceCurrentItem() {
        guard queue.indices.contains(currentIndex),
              let url = queue[currentIndex].previewURL else {
            player.replaceCurrentItem(with: nil)
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
}

private extension Double {
    var finiteValue: Double? {
        isFinite ? self : nil
    }

    var positiveFiniteValue: Double? {
        isFinite && self > 0 ? self : nil
    }
}
