import Foundation

enum ListeningPlaybackSource: Equatable, Sendable {
    case fullCatalog
    case preview
}

enum ListeningPlaybackSourceResolver {
    static func resolve(
        capability: ListeningMusicCapability,
        access: ListeningMusicAccess,
        establishedSource: ListeningPlaybackSource?
    ) -> ListeningPlaybackSource? {
        if establishedSource == .fullCatalog,
           access.authorizationStatus == .authorized,
           access.catalogPlaybackAccess == .accessCheckFailed {
            return .fullCatalog
        }
        return resolve(capability: capability)
    }

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

    /// Playing, or committed to playing while media buffers or seeks.
    var isActive: Bool {
        switch self {
        case .playing, .waiting, .seeking:
            true
        case .stopped, .paused, .interrupted:
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

    static func hasEnded(
        currentTime: TimeInterval,
        duration: TimeInterval?,
        phase: ListeningPlaybackTransportPhase
    ) -> Bool {
        guard phase == .paused || phase == .stopped else { return false }
        return hasEnded(
            currentTime: currentTime,
            duration: duration,
            isPlaying: false
        )
    }
}

enum ListeningPlayPauseAction: Equatable, Sendable {
    case play
    case pause
    case disabled
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

/// One Apple player per source. The player is the single source of truth:
/// `phase`, `currentSongID`, `hasEnded` and `failure` are observable (MusicKit
/// player state and queue on iOS 26.4+, AVFoundation with
/// `AVPlayer.isObservationEnabled`), so the deck and SwiftUI read them directly.
@MainActor
protocol ListeningPlaybackServicing: AnyObject {
    var source: ListeningPlaybackSource { get }
    var phase: ListeningPlaybackTransportPhase { get }
    var currentSongID: String? { get }
    var hasEnded: Bool { get }
    var failure: ListeningPlaybackError? { get }
    /// Song IDs of the loaded queue in play order. Items the player cannot play are left out.
    var queuedSongIDs: [String] { get }
    /// Continuous state: sample it, don't observe it.
    var currentTime: TimeInterval { get }
    var currentDuration: TimeInterval? { get }

    /// Resolves catalog items ahead of playback without touching the audio session.
    func prefetch(_ items: [ListeningPlaybackItem]) async
    /// Replaces the queue and buffers its starting entry at `time`.
    func load(_ items: [ListeningPlaybackItem], startingAt songID: String?, at time: TimeInterval) async throws
    func play() async throws
    func pause()
    func skipToNext() async throws
    func skipToPrevious() async throws
    /// Moves to a queued song, keeping playback running if it was running.
    func skip(to songID: String) async throws
    func stop()
}

@MainActor extension ListeningPlaybackServicing {
    func prefetch(_ items: [ListeningPlaybackItem]) async {}
}
