import Foundation

enum ListeningPlaybackSource: Equatable, Sendable {
    case fullCatalog
    case preview
}

enum ListeningPlaybackSourceResolver {
    static func resolve(capability: ListeningMusicCapability) -> ListeningPlaybackSource? {
        switch capability {
        case .fullPlayback:
            .fullCatalog
        case .previewOnly:
            .preview
        case .metadataOnly, .unavailable:
            nil
        }
    }
}

struct ListeningPlaybackItem: Equatable, Sendable {
    let songID: String
    let duration: TimeInterval?
    let previewURL: URL?
    let title: String?
    let artistName: String?

    init(
        songID: String,
        duration: TimeInterval?,
        previewURL: URL?,
        title: String? = nil,
        artistName: String? = nil
    ) {
        self.songID = songID
        self.duration = duration
        self.previewURL = previewURL
        self.title = title
        self.artistName = artistName
    }
}

struct ListeningPlaybackSample: Equatable, Sendable {
    let songID: String
    let source: ListeningPlaybackSource
    let currentTime: TimeInterval
    let duration: TimeInterval?
    let isPlaying: Bool
    let observedAt: Date
    let hasEnded: Bool

    init(
        songID: String,
        source: ListeningPlaybackSource,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool,
        observedAt: Date,
        hasEnded: Bool = false
    ) {
        self.songID = songID
        self.source = source
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.observedAt = observedAt
        self.hasEnded = hasEnded
    }
}

enum ListeningPlaybackCompletionPolicy {
    static func hasEnded(
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool
    ) -> Bool {
        guard !isPlaying, let duration, duration > 0 else { return false }
        return currentTime >= duration - 0.25
    }
}

enum ListeningPlaybackState: Equatable, Sendable {
    case idle
    case preparing(source: ListeningPlaybackSource)
    case ready(
        songID: String,
        source: ListeningPlaybackSource,
        currentTime: TimeInterval,
        duration: TimeInterval?
    )
    case playing(
        songID: String,
        source: ListeningPlaybackSource,
        currentTime: TimeInterval,
        duration: TimeInterval?
    )
    case paused(
        songID: String,
        source: ListeningPlaybackSource,
        currentTime: TimeInterval,
        duration: TimeInterval?
    )
    case finished(songID: String, source: ListeningPlaybackSource, duration: TimeInterval?)
    case failed

    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}

enum ListeningPlaybackEvent: Equatable, Sendable {
    case prepareStarted(source: ListeningPlaybackSource)
    case sample(ListeningPlaybackSample)
    case finished(songID: String)
    case failed
    case reset
}

struct ListeningPlaybackStateMachine {
    private(set) var state: ListeningPlaybackState = .idle

    @discardableResult
    mutating func handle(_ event: ListeningPlaybackEvent) -> ListeningPlaybackState {
        switch event {
        case let .prepareStarted(source):
            state = .preparing(source: source)
        case let .sample(sample):
            state = state(for: sample)
        case let .finished(songID):
            if let current = currentTrack, current.songID == songID {
                state = .finished(songID: songID, source: current.source, duration: current.duration)
            }
        case .failed:
            state = .failed
        case .reset:
            state = .idle
        }
        return state
    }

    private func state(for sample: ListeningPlaybackSample) -> ListeningPlaybackState {
        if sample.hasEnded {
            return .finished(songID: sample.songID, source: sample.source, duration: sample.duration)
        }
        if sample.isPlaying {
            return .playing(
                songID: sample.songID,
                source: sample.source,
                currentTime: sample.currentTime,
                duration: sample.duration
            )
        }
        if currentTrack?.songID == sample.songID {
            switch state {
            case .playing, .paused:
                return .paused(
                    songID: sample.songID,
                    source: sample.source,
                    currentTime: sample.currentTime,
                    duration: sample.duration
                )
            default:
                break
            }
        }
        return .ready(
            songID: sample.songID,
            source: sample.source,
            currentTime: sample.currentTime,
            duration: sample.duration
        )
    }

    private var currentTrack: (songID: String, source: ListeningPlaybackSource, duration: TimeInterval?)? {
        switch state {
        case let .ready(songID, source, _, duration),
             let .playing(songID, source, _, duration),
             let .paused(songID, source, _, duration),
             let .finished(songID, source, duration):
            (songID, source, duration)
        case .idle, .preparing, .failed:
            nil
        }
    }
}

enum ListeningPlaybackEvidenceUpdate: Equatable {
    case none
    case becameFamiliar(songID: String)
}

struct ListeningPlaybackEvidenceTracker {
    private let observationTolerance: TimeInterval
    private var currentSongID: String?
    private var lastSample: ListeningPlaybackSample?
    private var listenedDuration: TimeInterval = 0
    private var recordedSongIDs: Set<String>
    private var pendingSongID: String?

    init(
        alreadyRecordedSongIDs: Set<String> = [],
        observationTolerance: TimeInterval = 1.5
    ) {
        recordedSongIDs = alreadyRecordedSongIDs
        self.observationTolerance = observationTolerance
    }

    mutating func breakContinuity() {
        lastSample = nil
    }

    mutating func ingest(_ sample: ListeningPlaybackSample) -> ListeningPlaybackEvidenceUpdate {
        if sample.songID != currentSongID {
            currentSongID = sample.songID
            lastSample = nil
            listenedDuration = 0
        }
        defer { lastSample = sample }

        if let pendingSongID {
            return .becameFamiliar(songID: pendingSongID)
        }

        guard sample.source == .fullCatalog,
              let duration = sample.duration,
              duration > 0,
              let previous = lastSample,
              previous.songID == sample.songID,
              previous.source == .fullCatalog,
              previous.isPlaying else {
            return .none
        }

        let playbackDelta = sample.currentTime - previous.currentTime
        let observationDelta = sample.observedAt.timeIntervalSince(previous.observedAt)
        guard playbackDelta > 0,
              observationDelta >= 0,
              playbackDelta <= observationDelta + observationTolerance else {
            return .none
        }

        listenedDuration += playbackDelta
        guard listenedDuration > duration / 2,
              !recordedSongIDs.contains(sample.songID) else {
            return .none
        }
        pendingSongID = sample.songID
        return .becameFamiliar(songID: sample.songID)
    }

    mutating func commitFamiliarity(songID: String) {
        recordedSongIDs.insert(songID)
        if pendingSongID == songID {
            pendingSongID = nil
        }
    }
}

enum ListeningPlaybackError: Error, Equatable {
    case emptyQueue
    case queueBoundary
    case songUnavailable(String)
    case unsupportedSource
}

@MainActor
protocol ListeningPlaybackServicing: AnyObject {
    var failure: ListeningPlaybackError? { get }
    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws
    func play() async throws
    func pause()
    func skipToNext() async throws
    func skipToPrevious() async throws
    func seek(to time: TimeInterval)
    func snapshot(observedAt: Date) -> ListeningPlaybackSample?
    func stop()
}

@MainActor extension ListeningPlaybackServicing {
    var failure: ListeningPlaybackError? { nil }
}
