import AVFoundation
import Foundation

@MainActor
final class PreviewListeningPlaybackService: ListeningPlaybackServicing {
    private let player: AVQueuePlayer
    private var queue: [ListeningPlaybackItem] = []
    private var currentIndex = 0
    private var itemIndexes: [ObjectIdentifier: Int] = [:]

    init(player: AVQueuePlayer = AVQueuePlayer()) {
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
        rebuildPlayerQueue(startingAt: currentIndex)
    }

    func play() async throws {
        if player.currentItem?.status == .failed {
            replaceCurrentItem()
        }
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
        let index = activeIndex()
        guard index + 1 < queue.count else { throw ListeningPlaybackError.queueBoundary }
        let shouldResume = player.timeControlStatus == .playing
        player.advanceToNextItem()
        currentIndex = index + 1
        if shouldResume { player.play() }
    }

    func skipToPrevious() async throws {
        guard !queue.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        let index = activeIndex()
        guard index > 0 else { throw ListeningPlaybackError.queueBoundary }
        let shouldResume = player.timeControlStatus == .playing
        currentIndex = index - 1
        rebuildPlayerQueue(startingAt: currentIndex)
        if shouldResume { player.play() }
    }

    func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

    var failure: ListeningPlaybackError? {
        guard player.currentItem?.status == .failed else { return nil }
        let index = activeIndex()
        guard queue.indices.contains(index) else { return nil }
        return .songUnavailable(queue[index].songID)
    }

    func snapshot(observedAt: Date = Date()) -> ListeningPlaybackSample? {
        guard !queue.isEmpty else { return nil }
        let index = activeIndex()
        guard queue.indices.contains(index) else { return nil }
        let item = queue[index]
        let currentItem = player.currentItem
        let playerTime = currentItem == nil ? nil : player.currentTime().seconds.finiteValue
        let playerDuration = currentItem?.duration.seconds.positiveFiniteValue
        let duration = playerDuration ?? item.duration
        let reachedQueueEnd = currentItem == nil && index == queue.count - 1
        let currentTime = max(0, playerTime ?? (reachedQueueEnd ? duration ?? 0 : 0))
        let isPlaying = player.timeControlStatus == .playing
        return ListeningPlaybackSample(
            songID: item.songID,
            source: .preview,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            observedAt: observedAt,
            hasEnded: reachedQueueEnd || ListeningPlaybackCompletionPolicy.hasEnded(
                currentTime: currentTime,
                duration: duration,
                isPlaying: isPlaying
            )
        )
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        queue = []
        currentIndex = 0
        itemIndexes = [:]
        AppAudioSession.configureAmbient()
    }

    private func activeIndex() -> Int {
        guard let currentItem = player.currentItem,
              let index = itemIndexes[ObjectIdentifier(currentItem)] else {
            return currentIndex
        }
        currentIndex = index
        return index
    }

    private func rebuildPlayerQueue(startingAt index: Int) {
        player.removeAllItems()
        itemIndexes = [:]
        guard queue.indices.contains(index) else { return }

        var previous: AVPlayerItem?
        for queueIndex in index..<queue.count {
            guard let url = queue[queueIndex].previewURL else { continue }
            let item = AVPlayerItem(url: url)
            itemIndexes[ObjectIdentifier(item)] = queueIndex
            player.insert(item, after: previous)
            previous = item
        }
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
