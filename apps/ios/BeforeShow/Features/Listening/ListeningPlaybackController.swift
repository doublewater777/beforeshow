import Foundation

enum ListeningPlaybackEvidenceFailureOrigin: Equatable, Sendable {
    case immediate
    case deferred
}

@MainActor
final class ListeningPlaybackController {
    private let service: ListeningPlaybackServicing
    private let evidenceCoordinator: ListeningPlaybackEvidenceCoordinator
    private let playbackDidChange: @MainActor (ListeningPlaybackSnapshot) -> Void
    private let transportSampleDidChange: @MainActor (ListeningPlaybackSample) -> Void
    private let evidenceDidChange: @MainActor () -> Void
    private let evidenceDidFail: @MainActor (ListeningPlaybackEvidenceFailureOrigin) -> Void

    private var session = ListeningPlaybackSession()
    private var lastPublishedPlayback: ListeningPlaybackSnapshot?

    private var transportObservationTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var evidenceFlushTask: Task<Void, Never>?

    var playback: ListeningPlaybackSnapshot { session.snapshot }
    var state: ListeningPlaybackState { playback.state }
    var playbackIntent: ListeningPlaybackTransportTarget? { playback.intent }
    var pendingPlaybackIntent: ListeningPlaybackTransportTarget? { playback.pendingIntent }
    var wantsPlayback: Bool { playback.wantsPlayback }

    init(
        service: ListeningPlaybackServicing,
        evidenceCoordinator: ListeningPlaybackEvidenceCoordinator,
        playbackDidChange: @escaping @MainActor (ListeningPlaybackSnapshot) -> Void = { _ in },
        transportSampleDidChange: @escaping @MainActor (ListeningPlaybackSample) -> Void = { _ in },
        evidenceDidChange: @escaping @MainActor () -> Void = {},
        evidenceDidFail: @escaping @MainActor (ListeningPlaybackEvidenceFailureOrigin) -> Void = { _ in }
    ) {
        self.service = service
        self.evidenceCoordinator = evidenceCoordinator
        self.playbackDidChange = playbackDidChange
        self.transportSampleDidChange = transportSampleDidChange
        self.evidenceDidChange = evidenceDidChange
        self.evidenceDidFail = evidenceDidFail
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String? = nil,
        playbackIntent: ListeningPlaybackTransportTarget? = nil,
        now: Date = Date()
    ) async throws {
        cancelRuntimeObservation()
        session.prepare(source: source, intent: playbackIntent)
        publishPlayback()

        do {
            try await service.prepare(
                items: items,
                source: source,
                startingAtSongID: startingAtSongID
            )
            guard let initial = service.snapshot(observedAt: now) else {
                throw ListeningPlaybackError.songUnavailable(startingAtSongID ?? items.first?.songID ?? "")
            }

            ListeningRemoteCommandBridge.shared.attach(controller: self, items: items)
            try applyTransport(sample: initial, now: now, evidence: .immediate)
            startTransportObservation()
            startProgressClock()
        } catch {
            session.fail()
            publishPlayback()
            throw error
        }
    }

    func play(now: Date = Date()) async throws {
        session.request(.playing)
        publishPlayback()
        do {
            try await service.play()
            try sampleCommandAcknowledgement(now: now)
        } catch {
            session.fail()
            publishPlayback()
            throw error
        }
    }

    func pause(now: Date = Date()) throws {
        session.request(.paused)
        publishPlayback()
        service.pause()
        if try !sampleCommandAcknowledgement(now: now) {
            publishPlayback()
        }
    }

    /// Fast acknowledgement for transports that update synchronously. A stale
    /// snapshot cannot undo the pending presentation intent; Observable transport
    /// events remain the authoritative ongoing synchronization mechanism.
    @discardableResult
    private func sampleCommandAcknowledgement(now: Date) throws -> Bool {
        guard service.failure == nil,
              let sample = service.snapshot(observedAt: now) else { return false }
        try applyTransport(sample: sample, now: now, evidence: .deferred)
        return true
    }

    func skipToNext(now: Date = Date()) async throws {
        try captureProgressBoundary(now: now)
        try await service.skipToNext()
        evidenceCoordinator.breakContinuity()
        // Queue-entry changes normally arrive through transportEvents(). Keep an
        // explicit read as command-boundary recovery for adapters/tests that do
        // not expose a live event stream.
        _ = try resynchronizeTransport(now: now)
    }

    func skipToPrevious(now: Date = Date()) async throws {
        try captureProgressBoundary(now: now)
        try await service.skipToPrevious()
        evidenceCoordinator.breakContinuity()
        _ = try resynchronizeTransport(now: now)
    }

    func seek(to time: TimeInterval, now: Date = Date()) throws {
        try captureProgressBoundary(now: now)
        service.seek(to: time)
        evidenceCoordinator.breakContinuity()
        if let sample = service.snapshot(observedAt: now) {
            try applyProgress(sample: sample, now: now, evidence: .deferred)
        }
    }

    /// Synchronous truth resynchronization for lifecycle and command boundaries.
    /// It updates the UI immediately but keeps evidence persistence deferred.
    @discardableResult
    func resynchronizeTransport(now: Date = Date()) throws -> ListeningPlaybackState {
        if service.failure != nil {
            session.fail()
            publishPlayback()
            return state
        }
        guard let sample = service.snapshot(observedAt: now) else {
            return state
        }
        try applyTransport(sample: sample, now: now, evidence: .deferred)
        return state
    }

    /// Explicit recovery hook retained for lifecycle/tests. Normal playback status
    /// synchronization is driven by `transportEvents()`, not by this method.
    @discardableResult
    func refresh(now: Date = Date()) throws -> ListeningPlaybackState {
        if service.failure != nil {
            session.fail()
            publishPlayback()
            return state
        }
        guard let sample = service.snapshot(observedAt: now) else {
            return state
        }
        try applyTransport(sample: sample, now: now, evidence: .immediate)
        return state
    }

    func flushPendingEvidence() throws {
        handleEvidenceDrainResult(
            try evidenceCoordinator.flushPending(),
            failureOrigin: .immediate
        )
    }

    func stop(now: Date = Date()) throws {
        cancelRuntimeObservation()

        defer {
            service.stop()
            evidenceCoordinator.breakContinuity()
            session.reset()
            publishPlayback()
            lastPublishedPlayback = nil
            ListeningRemoteCommandBridge.shared.detach(controller: self)
        }

        evidenceFlushTask?.cancel()
        evidenceFlushTask = nil
        if service.failure == nil,
           let sample = service.snapshot(observedAt: now) {
            ListeningRemoteCommandBridge.shared.update(controller: self, sample: sample)
            _ = evidenceCoordinator.record(sample, at: now)
        }
        try flushPendingEvidence()
    }

    private enum EvidenceHandling {
        case immediate
        case deferred
    }

    private func applyTransport(
        sample: ListeningPlaybackSample,
        now: Date,
        evidence: EvidenceHandling
    ) throws {
        if playback.pendingIntent == .paused,
           sample.phase.satisfiesPlayIntent {
            // A pending Pause must defeat a system auto-resume or a slow Play.
            // Reassert before publishing the resumed sample. If Pause takes effect
            // synchronously, consume only the corrected transport sample so stale
            // resumed truth never reaches evidence/Now Playing/coordinator side effects.
            service.pause()
            if let corrected = service.snapshot(observedAt: now),
               !corrected.phase.satisfiesPlayIntent {
                try applyTransport(sample: corrected, now: now, evidence: evidence)
                return
            }
        }

        session.receive(sample)
        publishPlayback()

        transportSampleDidChange(sample)
        ListeningRemoteCommandBridge.shared.update(controller: self, sample: sample)
        try recordEvidence(sample, now: now, handling: evidence)
    }

    private func applyProgress(
        sample: ListeningPlaybackSample,
        now: Date,
        evidence: EvidenceHandling
    ) throws {
        session.progress(sample)
        publishPlayback()
        transportSampleDidChange(sample)
        ListeningRemoteCommandBridge.shared.update(controller: self, sample: sample)
        try recordEvidence(sample, now: now, handling: evidence)
    }

    private func recordEvidence(
        _ sample: ListeningPlaybackSample,
        now: Date,
        handling: EvidenceHandling
    ) throws {
        switch handling {
        case .immediate:
            handleEvidenceDrainResult(
                try evidenceCoordinator.ingest(sample, at: now),
                failureOrigin: .immediate
            )
        case .deferred:
            _ = evidenceCoordinator.record(sample, at: now)
            scheduleEvidenceFlush()
        }
    }

    private func scheduleEvidenceFlush() {
        guard evidenceFlushTask == nil else { return }
        evidenceFlushTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.evidenceFlushTask = nil
            do {
                self.handleEvidenceDrainResult(
                    try self.evidenceCoordinator.flushPending(),
                    failureOrigin: .deferred
                )
            } catch {
                self.evidenceDidFail(.deferred)
            }
        }
    }

    private func captureProgressBoundary(now: Date) throws {
        guard service.failure == nil,
              let sample = service.snapshot(observedAt: now) else { return }
        try applyProgress(sample: sample, now: now, evidence: .deferred)
    }

    private func handleEvidenceDrainResult(
        _ result: ListeningPlaybackEvidenceDrainResult,
        failureOrigin: ListeningPlaybackEvidenceFailureOrigin
    ) {
        if result.committedAny {
            evidenceDidChange()
        }
        if result.hasFailure {
            evidenceDidFail(failureOrigin)
        }
    }

    private func publishPlayback() {
        let snapshot = playback
        guard lastPublishedPlayback != snapshot else { return }
        lastPublishedPlayback = snapshot
        playbackDidChange(snapshot)
    }

    private func startTransportObservation() {
        transportObservationTask?.cancel()
        transportObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await sample in self.service.transportEvents() {
                if Task.isCancelled { return }
                if self.service.failure != nil {
                    self.session.fail()
                    self.publishPlayback()
                    continue
                }
                do {
                    // Observable transport events are authoritative transport truth.
                    // Pending intent clears only when that truth acknowledges the command.
                    try self.applyTransport(sample: sample, now: sample.observedAt, evidence: .deferred)
                } catch {
                    self.evidenceDidFail(.deferred)
                }
            }
        }
    }

    /// Discrete phase/queue changes are event-driven. The only periodic sampling
    /// left in the session is playback time, which AVFoundation explicitly treats
    /// as continuous state rather than ordinary observable state.
    private func startProgressClock() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                guard self.state.isPlaying,
                      self.service.failure == nil,
                      let sample = self.service.snapshot(observedAt: Date()) else {
                    continue
                }
                do {
                    try self.applyProgress(sample: sample, now: sample.observedAt, evidence: .deferred)
                } catch {
                    self.evidenceDidFail(.deferred)
                }
            }
        }
    }

    private func cancelRuntimeObservation() {
        transportObservationTask?.cancel()
        transportObservationTask = nil
        progressTask?.cancel()
        progressTask = nil
        evidenceFlushTask?.cancel()
        evidenceFlushTask = nil
    }
}
