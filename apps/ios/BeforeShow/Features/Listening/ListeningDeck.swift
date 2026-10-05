import Foundation

/// The CD player's transport. It owns what is loaded (the queue and the
/// cursor) and defers everything else to the Apple player of the active
/// source: transport state is read from that player, never mirrored. Commands
/// take effect immediately and the latest one wins.
@MainActor @Observable
final class ListeningDeck {
    enum Command: Equatable {
        case play
        case pause
    }

    /// Loaded records in play order. A show compilation spans its volumes.
    private(set) var discs: [ListeningDisc] = []
    private(set) var cursorSongID: String?
    /// Where the next cold start resumes, e.g. a disc restored after relaunch.
    private(set) var resumeTime: TimeInterval = 0
    /// A command the player has not acknowledged yet.
    private(set) var command: Command?
    private(set) var failed = false
    private(set) var engine: (any ListeningPlaybackServicing)?
    /// Whether `engine` holds this queue. Without it, navigation only moves the cursor.
    private(set) var isQueueLoaded = false

    @ObservationIgnored var onCursorChange: (String) -> Void = { _ in }
    @ObservationIgnored var onTransportChange: () -> Void = {}
    @ObservationIgnored var onProgress: (TimeInterval) -> Void = { _ in }
    @ObservationIgnored var onEvidence: (ListeningPlaybackEvidenceDrainResult, _ immediate: Bool) -> Void = { _, _ in }
    @ObservationIgnored var onFailure: () -> Void = {}
    @ObservationIgnored var evidenceProvider: () -> ListeningPlaybackEvidenceCoordinator? = { nil }
    /// Clock for listening samples.
    @ObservationIgnored var now: () -> Date = Date.init

    @ObservationIgnored private let makeEngine: @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var commandGeneration = 0
    @ObservationIgnored private var acknowledgementTimeout: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var lastTransport: Transport?

    init(makeEngine: @escaping @MainActor (ListeningPlaybackSource) -> any ListeningPlaybackServicing) {
        self.makeEngine = makeEngine
    }

    // MARK: - State

    var tracks: [ListeningDiscTrack] { discs.flatMap(\.tracks) }

    var currentTrack: ListeningDiscTrack? {
        guard let cursorSongID else { return nil }
        return tracks.first { $0.id == cursorSongID }
    }

    /// The record holding the cursor; for a compilation, the visible volume.
    var currentDisc: ListeningDisc? {
        guard let cursorSongID else { return discs.first }
        return discs.first { $0.tracks.contains { $0.id == cursorSongID } } ?? discs.first
    }

    /// The source of the established session, or of the one being started.
    var source: ListeningPlaybackSource? {
        guard isQueueLoaded || command == .play else { return nil }
        return engine?.source
    }

    var isFinished: Bool { isQueueLoaded && engine?.hasEnded == true }

    var isPlaying: Bool { isQueueLoaded && engine?.phase == .playing }

    var wantsPlayback: Bool { phase.isPlaybackActive }

    var time: TimeInterval {
        guard isQueueLoaded, let engine else { return resumeTime }
        // The player has not reached a newly selected song yet.
        guard engine.currentSongID == cursorSongID else { return 0 }
        return engine.currentTime
    }

    var duration: TimeInterval? {
        guard isQueueLoaded, let engine else { return currentTrack?.duration }
        return engine.currentDuration ?? currentTrack?.duration
    }

    var phase: ListeningPlayerPhase {
        if failed { return .failed }
        switch command {
        case .pause:
            return .paused
        case .play:
            guard isQueueLoaded, let engine, engine.currentSongID == cursorSongID else { return .preparing }
            switch engine.phase {
            case .playing: return .playing
            case .seeking: return .seeking
            default: return .waiting
            }
        case nil:
            break
        }
        guard isQueueLoaded, let engine else { return .stopped }
        if engine.hasEnded { return .finished }
        switch engine.phase {
        case .playing: return .playing
        case .waiting: return .waiting
        case .seeking: return .seeking
        case .paused: return .paused
        case .interrupted: return .interrupted
        case .stopped: return .stopped
        }
    }

    /// Next or previous song in the loaded records' track order.
    func adjacentSongID(_ delta: Int) -> String? {
        guard delta != 0, let cursorSongID else { return nil }
        let order = tracks.map(\.id)
        guard let index = order.firstIndex(of: cursorSongID),
              order.indices.contains(index + delta) else { return nil }
        return order[index + delta]
    }

    // MARK: - Loading

    /// Puts records in the tray. Playing anything else stops first.
    func load(_ discs: [ListeningDisc], cursor songID: String?, resumeAt time: TimeInterval = 0) {
        let tracks = discs.flatMap(\.tracks)
        let cursor = songID.flatMap { id in tracks.contains { $0.id == id } ? id : nil } ?? tracks.first?.id
        unloadQueue()
        self.discs = discs
        cursorSongID = cursor
        resumeTime = time.isFinite ? max(0, time) : 0
        failed = false
        command = nil
    }

    /// Refreshes the records behind an idle cursor, e.g. once the catalog
    /// can supply every compilation volume.
    func replaceIdleDiscs(_ discs: [ListeningDisc]) {
        guard !isQueueLoaded, command == nil, discs != self.discs,
              let cursorSongID,
              discs.contains(where: { $0.tracks.contains { $0.id == cursorSongID } }) else { return }
        self.discs = discs
    }

    func eject() {
        unloadQueue()
        discs = []
        cursorSongID = nil
        resumeTime = 0
        failed = false
        command = nil
    }

    /// Resolves catalog items for the loaded records without touching audio.
    func prefetch(source: ListeningPlaybackSource) {
        guard !isQueueLoaded, command == nil, !tracks.isEmpty else { return }
        let engine = engine(for: source)
        let items = tracks.map(\.playbackItem)
        prefetchTask?.cancel()
        prefetchTask = Task { await engine.prefetch(items) }
    }

    // MARK: - Transport commands

    func play(source: ListeningPlaybackSource) {
        syncWithPlayer()
        guard let cursor = cursorSongID else { return }
        let engine = engine(for: source)
        let needsLoad = !isQueueLoaded || engine.hasEnded || engine.failure != nil
        let resume = isQueueLoaded ? 0 : resumeTime
        let items = tracks.map(\.playbackItem)
        failed = false
        command = .play
        if needsLoad {
            isQueueLoaded = false
        }
        perform { [weak self] engine in
            if needsLoad {
                try await engine.load(items, startingAt: cursor, at: resume)
                try Task.checkCancellation()
                self?.queueDidLoad()
            }
            try await engine.play()
        }
        onTransportChange()
    }

    func pause() {
        syncWithPlayer()
        cancelCommand()
        guard isQueueLoaded, let engine else {
            command = nil
            onTransportChange()
            return
        }
        recordSample(immediate: true)
        engine.pause()
        // A pause during an interruption must also outlast the system's auto-resume.
        command = engine.phase.isActive || engine.phase == .interrupted ? .pause : nil
        expectAcknowledgement()
        onTransportChange()
    }

    func togglePlayPause(source: ListeningPlaybackSource?) {
        if wantsPlayback {
            pause()
        } else if let source {
            play(source: source)
        }
    }

    /// Moves the cursor. Playback continues on the new song when it was
    /// running or `autoplay` asks for it, and a `nil` source ends it.
    func select(_ songID: String, autoplay: Bool, source: ListeningPlaybackSource?) {
        syncWithPlayer()
        guard tracks.contains(where: { $0.id == songID }) else { return }
        let continues = autoplay || wantsPlayback
        if songID == cursorSongID, isQueueLoaded, !isFinished {
            if continues, !wantsPlayback, let source { play(source: source) }
            return
        }
        if continues, let source, isQueueLoaded, let engine, engine.source == source,
           engine.failure == nil, engine.queuedSongIDs.contains(songID) {
            recordSample(immediate: false)
            moveCursor(to: songID)
            failed = false
            command = .play
            perform { engine in
                if engine.currentSongID != songID {
                    try await engine.skip(to: songID)
                }
                if !engine.phase.isActive {
                    try await engine.play()
                }
            }
            onTransportChange()
            return
        }
        unloadQueue()
        command = nil
        failed = false
        resumeTime = 0
        moveCursor(to: songID)
        if continues, let source {
            play(source: source)
        } else {
            onTransportChange()
        }
    }

    /// Next/previous track: native queue navigation while the loaded queue
    /// plays, a cursor move otherwise. A target the source cannot play ends playback.
    func skip(by delta: Int, source: ListeningPlaybackSource?) {
        syncWithPlayer()
        guard let target = adjacentSongID(delta) else { return }
        guard isQueueLoaded, let engine, wantsPlayback, let source, engine.source == source,
              engine.queuedSongIDs.contains(target) else {
            select(target, autoplay: false, source: source)
            return
        }
        recordSample(immediate: false)
        moveCursor(to: target)
        command = .play
        perform { engine in
            // Decided against the player's position when the command runs, so
            // quick repeated taps stay correct while earlier ones are in flight.
            let queue = engine.queuedSongIDs
            let neighbor = engine.currentSongID
                .flatMap { queue.firstIndex(of: $0) }
                .flatMap { queue.indices.contains($0 + delta) ? queue[$0 + delta] : nil }
            if neighbor == target, delta == 1 {
                try await engine.skipToNext()
            } else if neighbor == target, delta == -1 {
                try await engine.skipToPrevious()
            } else if engine.currentSongID != target {
                try await engine.skip(to: target)
            }
        }
        onTransportChange()
    }

    /// The Stop button: the record stays and returns to its first track.
    func stop() {
        syncWithPlayer()
        let first = currentDisc?.tracks.first?.id
        unloadQueue()
        command = nil
        failed = false
        resumeTime = 0
        if let first, first != cursorSongID {
            moveCursor(to: first)
        }
        onTransportChange()
    }

    /// Ends a session its source can no longer serve; the song and position stay.
    func endSession() {
        syncWithPlayer()
        let position = time
        unloadQueue()
        command = nil
        resumeTime = position
        onTransportChange()
    }

    /// Re-reads the player after the process could not consume observations.
    func resynchronize() {
        lastTransport = nil
        syncWithPlayer()
    }

    /// Commands act on the player's current state, even before its
    /// observation is delivered.
    private func syncWithPlayer() {
        guard let engine else { return }
        apply(Transport(engine), from: engine)
    }

    /// Waits for the latest command to reach the player.
    func settle() async {
        await commandTask?.value
    }

    // MARK: - Engine

    private func engine(for source: ListeningPlaybackSource) -> any ListeningPlaybackServicing {
        if let engine, engine.source == source { return engine }
        unloadQueue()
        let created = makeEngine(source)
        engine = created
        lastTransport = nil
        observe(created)
        return created
    }

    private func observe(_ engine: any ListeningPlaybackServicing) {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            let transport = Observations { [weak self] () -> Transport? in
                guard let engine = self?.engine else { return nil }
                return Transport(engine)
            }
            for await change in transport {
                guard let self, !Task.isCancelled else { return }
                guard let change, let engine = self.engine else { continue }
                self.apply(change, from: engine)
            }
        }
    }

    private func apply(_ change: Transport, from engine: any ListeningPlaybackServicing) {
        guard engine === self.engine, isQueueLoaded else { return }
        if change.failed {
            fail()
            return
        }
        // The player owns which song is current, except while our own
        // navigation is still on its way to it.
        if commandTask == nil, let songID = change.songID, songID != cursorSongID,
           tracks.contains(where: { $0.id == songID }) {
            evidenceProvider()?.breakContinuity()
            moveCursor(to: songID)
        }
        let commandBefore = command
        if command == .pause, change.phase.isActive {
            // The user's Pause outranks a system resume that raced it.
            engine.pause()
        }
        switch command {
        case .play where change.phase.isActive,
             .pause where !change.phase.isActive && change.phase != .interrupted:
            command = nil
        default:
            break
        }
        if change.ended {
            command = nil
        }
        guard change != lastTransport else {
            if command != commandBefore { onTransportChange() }
            return
        }
        let previous = lastTransport
        lastTransport = change
        if change.phase == .playing {
            if previous?.phase != .playing || previous?.songID != change.songID {
                // Baseline for this stretch of listening.
                recordSample(immediate: false)
            }
            startProgress()
        } else {
            if previous?.phase == .playing {
                // Playback stopped outside the app, e.g. from the Lock Screen.
                recordSample(immediate: false)
            }
            stopProgress()
        }
        onTransportChange()
    }

    private func perform(_ action: @escaping @MainActor (any ListeningPlaybackServicing) async throws -> Void) {
        guard let engine else { return }
        cancelCommand()
        commandGeneration += 1
        let generation = commandGeneration
        commandTask = Task { @MainActor [weak self] in
            do {
                try await action(engine)
                guard let self else { return }
                if Task.isCancelled {
                    // Pause, Stop or Eject won while Play was still reaching the player.
                    if generation == self.commandGeneration || !self.isQueueLoaded || self.engine !== engine {
                        engine.pause()
                    }
                    return
                }
                if generation == self.commandGeneration {
                    self.commandTask = nil
                }
                self.apply(Transport(engine), from: engine)
            } catch is CancellationError {
            } catch ListeningPlaybackError.queueBoundary {
                self?.command = nil
            } catch {
                guard let self, generation == self.commandGeneration else { return }
                self.fail()
            }
            guard let self, generation == self.commandGeneration else { return }
            self.commandTask = nil
            self.expectAcknowledgement()
        }
    }

    private func queueDidLoad() {
        isQueueLoaded = true
        resumeTime = 0
        lastTransport = nil
        evidenceProvider()?.breakContinuity()
        if let engine { apply(Transport(engine), from: engine) }
    }

    /// The player normally confirms within a moment. A command it never
    /// confirms must not hide the player's actual state indefinitely.
    private func expectAcknowledgement() {
        acknowledgementTimeout?.cancel()
        guard command != nil, commandTask == nil else { return }
        let generation = commandGeneration
        acknowledgementTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, generation == self.commandGeneration,
                  self.commandTask == nil, self.command != nil,
                  self.engine?.phase != .interrupted else { return }
            self.command = nil
            self.onTransportChange()
        }
    }

    private func cancelCommand() {
        commandTask?.cancel()
        commandTask = nil
        acknowledgementTimeout?.cancel()
        acknowledgementTimeout = nil
    }

    private func unloadQueue() {
        commandTask?.cancel()
        commandTask = nil
        commandGeneration += 1
        acknowledgementTimeout?.cancel()
        prefetchTask?.cancel()
        stopProgress()
        if isQueueLoaded, let engine {
            recordSample(immediate: true)
            engine.stop()
        } else {
            flushEvidence(immediate: true)
        }
        isQueueLoaded = false
        lastTransport = nil
        evidenceProvider()?.breakContinuity()
    }

    private func fail() {
        cancelCommand()
        commandGeneration += 1
        stopProgress()
        if isQueueLoaded {
            recordSample(immediate: true)
            engine?.stop()
        }
        isQueueLoaded = false
        lastTransport = nil
        command = nil
        failed = true
        onFailure()
        onTransportChange()
    }

    private func moveCursor(to songID: String) {
        guard songID != cursorSongID else { return }
        cursorSongID = songID
        onCursorChange(songID)
    }

    // MARK: - Progress and listening evidence

    private func startProgress() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard self.isPlaying, let engine = self.engine else { continue }
                self.recordSample(immediate: false)
                self.onProgress(engine.currentTime)
            }
        }
    }

    private func stopProgress() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func recordSample(immediate: Bool) {
        guard isQueueLoaded, let engine, let songID = engine.currentSongID,
              let evidence = evidenceProvider() else { return }
        evidence.record(ListeningPlaybackSample(
            songID: songID,
            source: engine.source,
            currentTime: engine.currentTime,
            duration: engine.currentDuration,
            phase: engine.phase,
            observedAt: now()
        ))
        flushEvidence(immediate: immediate)
    }

    private func flushEvidence(immediate: Bool) {
        guard let evidence = evidenceProvider() else { return }
        let result = (try? evidence.flushPending())
            ?? ListeningPlaybackEvidenceDrainResult(committedSongIDs: [], hasFailure: true)
        guard result.committedAny || result.hasFailure else { return }
        onEvidence(result, immediate)
    }
}

/// Discrete player truth the deck reacts to.
private struct Transport: Equatable, Sendable {
    let phase: ListeningPlaybackTransportPhase
    let songID: String?
    let ended: Bool
    let failed: Bool

    @MainActor init(_ engine: any ListeningPlaybackServicing) {
        phase = engine.phase
        songID = engine.currentSongID
        ended = engine.hasEnded
        failed = engine.failure != nil
    }
}
