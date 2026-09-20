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

enum ListeningPlaybackTransportPhase: Equatable, Sendable {
    case stopped
    case paused
    case playing
    case waiting
    case interrupted
    case seeking

    var isPlaying: Bool {
        self == .playing
    }

    var satisfiesPlayIntent: Bool {
        switch self {
        case .playing, .waiting, .seeking:
            true
        case .stopped, .paused, .interrupted:
            false
        }
    }

    var satisfiesPauseIntent: Bool {
        switch self {
        case .stopped, .paused, .interrupted:
            true
        case .playing, .waiting, .seeking:
            false
        }
    }
}

struct ListeningPlaybackSample: Equatable, Sendable {
    let songID: String
    let source: ListeningPlaybackSource
    let currentTime: TimeInterval
    let duration: TimeInterval?
    let phase: ListeningPlaybackTransportPhase
    let observedAt: Date
    let hasEnded: Bool

    var isPlaying: Bool { phase.isPlaying }

    init(
        songID: String,
        source: ListeningPlaybackSource,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool,
        observedAt: Date,
        hasEnded: Bool = false
    ) {
        self.init(
            songID: songID,
            source: source,
            currentTime: currentTime,
            duration: duration,
            phase: isPlaying ? .playing : .paused,
            observedAt: observedAt,
            hasEnded: hasEnded
        )
    }

    init(
        songID: String,
        source: ListeningPlaybackSource,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        phase: ListeningPlaybackTransportPhase,
        observedAt: Date,
        hasEnded: Bool = false
    ) {
        self.songID = songID
        self.source = source
        self.currentTime = currentTime
        self.duration = duration
        self.phase = phase
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

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }

    func projecting(_ target: ListeningPlaybackTransportTarget) -> ListeningPlaybackState {
        switch target {
        case .playing:
            switch self {
            case let .ready(songID, source, currentTime, duration),
                 let .playing(songID, source, currentTime, duration),
                 let .paused(songID, source, currentTime, duration):
                return .playing(
                    songID: songID,
                    source: source,
                    currentTime: currentTime,
                    duration: duration
                )
            case let .finished(songID, source, duration):
                return .playing(
                    songID: songID,
                    source: source,
                    currentTime: 0,
                    duration: duration
                )
            case .idle, .preparing, .failed:
                return self
            }
        case .paused:
            switch self {
            case let .playing(songID, source, currentTime, duration),
                 let .paused(songID, source, currentTime, duration):
                return .paused(
                    songID: songID,
                    source: source,
                    currentTime: currentTime,
                    duration: duration
                )
            case .idle, .preparing, .ready, .finished, .failed:
                return self
            }
        }
    }
}

enum ListeningPlaybackTransportTarget: Equatable, Sendable {
    case playing
    case paused

    func matches(_ sample: ListeningPlaybackSample) -> Bool {
        switch self {
        case .playing:
            sample.phase.satisfiesPlayIntent && !sample.hasEnded
        case .paused:
            sample.phase.satisfiesPauseIntent
        }
    }
}

struct ListeningPlaybackTransportIntent: Equatable, Sendable {
    let target: ListeningPlaybackTransportTarget
    let issuedAt: Date
}

enum ListeningPlaybackEvent: Equatable, Sendable {
    case prepareStarted(source: ListeningPlaybackSource)
    case sample(ListeningPlaybackSample)
    case progress(ListeningPlaybackSample)
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
            state = observedState(for: sample)
        case let .progress(sample):
            state = progressedState(for: sample)
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

    private func observedState(for sample: ListeningPlaybackSample) -> ListeningPlaybackState {
        if sample.hasEnded {
            return .finished(songID: sample.songID, source: sample.source, duration: sample.duration)
        }

        switch sample.phase {
        case .playing, .waiting, .seeking:
            return .playing(
                songID: sample.songID,
                source: sample.source,
                currentTime: sample.currentTime,
                duration: sample.duration
            )
        case .paused, .interrupted, .stopped:
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
    }

    private func progressedState(for sample: ListeningPlaybackSample) -> ListeningPlaybackState {
        guard currentTrack?.songID == sample.songID else { return state }

        switch state {
        case let .ready(songID, source, _, duration):
            return .ready(
                songID: songID,
                source: source,
                currentTime: sample.currentTime,
                duration: sample.duration ?? duration
            )
        case let .playing(songID, source, _, duration):
            return .playing(
                songID: songID,
                source: source,
                currentTime: sample.currentTime,
                duration: sample.duration ?? duration
            )
        case let .paused(songID, source, _, duration):
            return .paused(
                songID: songID,
                source: source,
                currentTime: sample.currentTime,
                duration: sample.duration ?? duration
            )
        case .idle, .preparing, .finished, .failed:
            return state
        }
    }

    private var currentTrack: (
        songID: String,
        source: ListeningPlaybackSource,
        duration: TimeInterval?
    )? {
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

struct ListeningPlaybackPendingFamiliarity: Equatable {
    let songID: String
    let familiarityReachedAt: Date
}

struct ListeningPlaybackEvidenceTracker {
    private let observationTolerance: TimeInterval
    private var currentSongID: String?
    private var lastSample: ListeningPlaybackSample?
    private var listenedDuration: TimeInterval = 0
    private var recordedSongIDs: Set<String>
    private var pendingFamiliarities: [ListeningPlaybackPendingFamiliarity] = []
    private var pendingSongIDSet: Set<String> = []

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

    mutating func ingest(
        _ sample: ListeningPlaybackSample,
        familiarityReachedAt: Date? = nil
    ) -> ListeningPlaybackEvidenceUpdate {
        if sample.songID != currentSongID {
            currentSongID = sample.songID
            lastSample = nil
            listenedDuration = 0
        }
        defer { lastSample = sample }

        guard sample.source == .fullCatalog,
              let duration = sample.duration,
              duration > 0,
              let previous = lastSample,
              previous.songID == sample.songID,
              previous.source == .fullCatalog,
              previous.isPlaying else {
            return pendingUpdate
        }

        let playbackDelta = sample.currentTime - previous.currentTime
        let observationDelta = sample.observedAt.timeIntervalSince(previous.observedAt)
        guard playbackDelta > 0,
              observationDelta >= 0,
              playbackDelta <= observationDelta + observationTolerance else {
            return pendingUpdate
        }

        listenedDuration += playbackDelta
        if listenedDuration > duration / 2,
           !recordedSongIDs.contains(sample.songID),
           pendingSongIDSet.insert(sample.songID).inserted {
            pendingFamiliarities.append(
                ListeningPlaybackPendingFamiliarity(
                    songID: sample.songID,
                    familiarityReachedAt: familiarityReachedAt ?? sample.observedAt
                )
            )
        }
        return pendingUpdate
    }

    var nextPendingFamiliarity: ListeningPlaybackPendingFamiliarity? {
        pendingFamiliarities.first
    }

    mutating func commitFamiliarity(songID: String) {
        recordedSongIDs.insert(songID)
        pendingSongIDSet.remove(songID)
        if let index = pendingFamiliarities.firstIndex(where: { $0.songID == songID }) {
            pendingFamiliarities.remove(at: index)
        }
    }

    private var pendingUpdate: ListeningPlaybackEvidenceUpdate {
        guard let pending = nextPendingFamiliarity else { return .none }
        return .becameFamiliar(songID: pending.songID)
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

    /// Discrete transport truth. Production adapters emit when playback status or
    /// the current queue entry changes. This is the normal synchronization path.
    func transportEvents() -> AsyncStream<ListeningPlaybackSample>

    /// Point-in-time transport read used for initial seeding, explicit recovery,
    /// and playback-time sampling. It is not the ongoing state synchronization path.
    func snapshot(observedAt: Date) -> ListeningPlaybackSample?
    func stop()
}

@MainActor extension ListeningPlaybackServicing {
    var failure: ListeningPlaybackError? { nil }

    func transportEvents() -> AsyncStream<ListeningPlaybackSample> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
