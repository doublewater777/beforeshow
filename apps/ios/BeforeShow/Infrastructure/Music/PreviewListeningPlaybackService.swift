import AVFoundation
import Foundation
import Observation

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
        if player.currentItem?.status == .failed || player.currentItem == nil {
            rebuildPlayerQueue(startingAt: activeIndex())
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
        let shouldResume = player.timeControlStatus != .paused
        player.advanceToNextItem()
        currentIndex = index + 1
        if shouldResume { player.play() }
    }

    func skipToPrevious() async throws {
        guard !queue.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        let index = activeIndex()
        guard index > 0 else { throw ListeningPlaybackError.queueBoundary }
        let shouldResume = player.timeControlStatus != .paused
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

    func transportEvents() -> AsyncStream<ListeningPlaybackSample> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                let observations = Observations {
                    PreviewTransportObservation(
                        status: self.player.timeControlStatus,
                        currentItemID: self.player.currentItem.map(ObjectIdentifier.init),
                        currentItemStatus: self.player.currentItem?.status
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
        let phase = transportPhase
        return ListeningPlaybackSample(
            songID: item.songID,
            source: .preview,
            currentTime: currentTime,
            duration: duration,
            phase: phase,
            observedAt: observedAt,
            hasEnded: reachedQueueEnd || ListeningPlaybackCompletionPolicy.hasEnded(
                currentTime: currentTime,
                duration: duration,
                phase: phase
            )
        )
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        queue = []
        currentIndex = 0
        itemIndexes = [:]
        AppAudioSession.releaseMusicPlayback()
    }

    private var transportPhase: ListeningPlaybackTransportPhase {
        guard player.currentItem != nil else { return .stopped }
        switch player.timeControlStatus {
        case .playing:
            .playing
        case .waitingToPlayAtSpecifiedRate:
            .waiting
        case .paused:
            .paused
        @unknown default:
            .paused
        }
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

private struct PreviewTransportObservation: Equatable, Sendable {
    let status: AVPlayer.TimeControlStatus
    let currentItemID: ObjectIdentifier?
    let currentItemStatus: AVPlayerItem.Status?
}
