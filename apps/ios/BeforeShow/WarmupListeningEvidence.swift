import Foundation

struct WarmupListeningEvidence {
    enum PlaybackSource {
        case appleMusicFullPlayback
        case appleMusicPreview
    }

    struct PlaybackSample {
        let songID: String
        let source: PlaybackSource
        let currentTime: TimeInterval
        let duration: TimeInterval?
        let isPlaying: Bool
    }

    enum UpdateResult: Equatable {
        case none
        case heard(songID: String)
        case manuallyMarked(songID: String)
    }

    private let maximumContinuousPlaybackDelta: TimeInterval
    private var currentSongID: String?
    private var lastSample: PlaybackSample?
    private var listenedDuration: TimeInterval = 0
    private var markedSongIDs = Set<String>()

    init(maximumContinuousPlaybackDelta: TimeInterval = 30) {
        self.maximumContinuousPlaybackDelta = maximumContinuousPlaybackDelta
    }

    mutating func update(_ sample: PlaybackSample) -> UpdateResult {
        if sample.songID != currentSongID {
            currentSongID = sample.songID
            lastSample = nil
            listenedDuration = 0
        }

        defer { lastSample = sample }

        guard sample.source == .appleMusicFullPlayback,
              sample.isPlaying,
              let duration = sample.duration,
              duration > 0,
              let lastSample,
              lastSample.source == .appleMusicFullPlayback,
              lastSample.isPlaying else {
            return .none
        }

        let playbackDelta = sample.currentTime - lastSample.currentTime
        guard playbackDelta > 0,
              playbackDelta <= maximumContinuousPlaybackDelta else {
            return .none
        }

        listenedDuration += playbackDelta

        guard listenedDuration >= duration / 2,
              !markedSongIDs.contains(sample.songID) else {
            return .none
        }

        markedSongIDs.insert(sample.songID)
        return .heard(songID: sample.songID)
    }

    mutating func markHeardManually(songID: String) -> UpdateResult {
        markedSongIDs.insert(songID)
        return .manuallyMarked(songID: songID)
    }
}
