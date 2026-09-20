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

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}

enum ListeningPlaybackTransportTarget: Equatable, Sendable {
    case playing
    case paused

    func matches(_ sample: ListeningPlaybackSample) -> Bool {
        switch self {
        case .playing:
            return sample.isPlaying && !sample.hasEnded
        case .paused:
            return !sample.isPlaying
        }
    }
}

struct ListeningPlaybackTransportIntent: Equatable, Sendable {
    let target: ListeningPlaybackTransportTarget
    let issuedAt: Date
}

enum ListeningPlaybackEvent: Equatable, Sendable {
    case prepareStarted(source: ListeningPlaybackSource)
    case transportRequested(ListeningPlaybackTransportIntent)
    case sample(ListeningPlaybackSample)
    case finished(songID: String)
    case failed
    case reset
}

struct ListeningPlaybackStateMachine {
    /// The controller owns continuous transport observation while prepared.
    /// A fresh play/pause command still gets a short acknowledgement grace window
    /// so a lagging transport sample cannot immediately undo the user's intent.
    static let transportAcknowledgementWindow: TimeInterval = 1.5

    private(set) var state: ListeningPlaybackState = .idle
    private(set) var pendingTransportIntent: ListeningPlaybackTransportIntent?

    @discardableResult
    mutating func handle(_ event: ListeningPlaybackEvent) -> ListeningPlaybackState {
        switch event {
        case let .prepareStarted(source):
            pendingTransportIntent = nil
            state = .preparing(source: source)
        case let .transportRequested(intent):
            pendingTransportIntent = intent
            state = state(for: intent.target)
        case let .sample(sample):
            state = reconciledState(for: sample)
        case let .finished(songID):
            pendingTransportIntent = nil
            if let current = currentTrack, current.songID == songID {
                state = .finished(songID: songID, source: current.source, duration: current.duration)
            }
        case .failed:
            pendingTransportIntent = nil
            state = .failed
        case .reset:
            pendingTransportIntent = nil
            state = .idle
        }
        return state
    }

    private mutating func reconciledState(
        for sample: ListeningPlaybackSample
    ) -> ListeningPlaybackState {
        guard let intent = pendingTransportIntent else {
            return observedState(for: sample)
        }

        if intent.target.matches(sample) {
            pendingTransportIntent = nil
            return observedState(for: sample)
        }

        let age = sample.observedAt.timeIntervalSince(intent.issuedAt)
        guard age >= 0, age <= Self.transportAcknowledgementWindow else {
            pendingTransportIntent = nil
            return observedState(for: sample)
        }

        return state(for: intent.target, using: sample)
    }

    private func state(
        for target: ListeningPlaybackTransportTarget
    ) -> ListeningPlaybackState {
        switch target {
        case .playing:
            switch state {
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
                return state
            }
        case .paused:
            switch state {
            case let .playing(songID, source, currentTime, duration),
                 let .paused(songID, source, currentTime, duration):
                return .paused(
                    songID: songID,
                    source: source,
                    currentTime: currentTime,
                    duration: duration
                )
            case .idle, .preparing, .ready, .finished, .failed:
                return state
            }
        }
    }

    private func state(
        for target: ListeningPlaybackTransportTarget,
        using sample: ListeningPlaybackSample
    ) -> ListeningPlaybackState {
        switch target {
        case .playing:
            if sample.hasEnded, state.isPlaying {
                return state
            }
            return .playing(
                songID: sample.songID,
                source: sample.source,
                currentTime: sample.currentTime,
                duration: sample.duration
            )
        case .paused:
            if sample.hasEnded {
                return .finished(
                    songID: sample.songID,
                    source: sample.source,
                    duration: sample.duration
                )
            }
            return .paused(
                songID: sample.songID,
                source: sample.source,
                currentTime: sample.currentTime,
                duration: sample.duration
            )
        }
    }

    private func observedState(for sample: ListeningPlaybackSample) -> ListeningPlaybackState {
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
    func snapshot(observedAt: Date) -> ListeningPlaybackSample?
    func stop()
}

@MainActor extension ListeningPlaybackServicing {
    var failure: ListeningPlaybackError? { nil }
}
