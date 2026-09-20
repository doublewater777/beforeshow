import Foundation
import MediaPlayer

enum ListeningPlaybackEvidenceFailureOrigin: Equatable, Sendable {
    case immediate
    case deferred
}

@MainActor
final class ListeningPlaybackController {
    /// Intent grace is presentation-only. Transport truth is never overwritten by
    /// the command; the pending intent merely gives the UI immediate feedback until
    /// the observable transport acknowledges it or the grace period expires.
    private static let transportAcknowledgementWindow: TimeInterval = 1.5

    private let service: ListeningPlaybackServicing
    private let evidenceCoordinator: ListeningPlaybackEvidenceCoordinator
    private let stateDidChange: @MainActor (ListeningPlaybackState) -> Void
    private let transportStateDidChange: @MainActor (ListeningPlaybackState) -> Void
    private let transportSampleDidChange: @MainActor (ListeningPlaybackSample) -> Void
    private let evidenceDidChange: @MainActor () -> Void
    private let evidenceDidFail: @MainActor (ListeningPlaybackEvidenceFailureOrigin) -> Void

    private var stateMachine = ListeningPlaybackStateMachine()
    private var pendingTransportIntent: ListeningPlaybackTransportIntent?
    private var lastPublishedState: ListeningPlaybackState?
    private var lastPublishedTransportState: ListeningPlaybackState?

    private var transportObservationTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var intentTimeoutTask: Task<Void, Never>?
    private var evidenceFlushTask: Task<Void, Never>?

    /// Product/UI projection. The underlying transport fact remains in
    /// `stateMachine.state` even while a command is awaiting acknowledgement.
    var state: ListeningPlaybackState {
        guard let pendingTransportIntent else { return stateMachine.state }
        return stateMachine.state.projecting(pendingTransportIntent.target)
    }

    var transportState: ListeningPlaybackState { stateMachine.state }

    init(
        service: ListeningPlaybackServicing,
        evidenceCoordinator: ListeningPlaybackEvidenceCoordinator,
        stateDidChange: @escaping @MainActor (ListeningPlaybackState) -> Void = { _ in },
        transportStateDidChange: @escaping @MainActor (ListeningPlaybackState) -> Void = { _ in },
        transportSampleDidChange: @escaping @MainActor (ListeningPlaybackSample) -> Void = { _ in },
        evidenceDidChange: @escaping @MainActor () -> Void = {},
        evidenceDidFail: @escaping @MainActor (ListeningPlaybackEvidenceFailureOrigin) -> Void = { _ in }
    ) {
        self.service = service
        self.evidenceCoordinator = evidenceCoordinator
        self.stateDidChange = stateDidChange
        self.transportStateDidChange = transportStateDidChange
        self.transportSampleDidChange = transportSampleDidChange
        self.evidenceDidChange = evidenceDidChange
        self.evidenceDidFail = evidenceDidFail
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String? = nil,
        now: Date = Date()
    ) async throws {
        cancelRuntimeObservation()
        clearPendingIntent()
        stateMachine.handle(.prepareStarted(source: source))
        publishState()

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
            stateMachine.handle(.failed)
            publishState()
            throw error
        }
    }

    func play(now: Date = Date()) async throws {
        beginIntent(.playing, now: now)
        do {
            try await service.play()
            try sampleCommandAcknowledgement(now: now)
        } catch {
            clearPendingIntent()
            stateMachine.handle(.failed)
            publishState()
            throw error
        }
    }

    func pause(now: Date = Date()) throws {
        beginIntent(.paused, now: now, publishImmediately: false)
        service.pause()
        if try !sampleCommandAcknowledgement(now: now) {
            publishState()
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
        clearPendingIntent()
        if service.failure != nil {
            clearPendingIntent()
            stateMachine.handle(.failed)
            publishState()
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
        clearPendingIntent()
        if service.failure != nil {
            clearPendingIntent()
            stateMachine.handle(.failed)
            publishState()
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
        clearPendingIntent()

        defer {
            service.stop()
            evidenceCoordinator.breakContinuity()
            stateMachine.handle(.reset)
            publishState()
            lastPublishedState = nil
            lastPublishedTransportState = nil
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

    private func beginIntent(
        _ target: ListeningPlaybackTransportTarget,
        now: Date,
        publishImmediately: Bool = true
    ) {
        let intent = ListeningPlaybackTransportIntent(target: target, issuedAt: now)
        pendingTransportIntent = intent
        if publishImmediately {
            publishState()
        }

        intentTimeoutTask?.cancel()
        intentTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(1_500))
            } catch {
                return
            }
            guard let self, self.pendingTransportIntent == intent else { return }
            self.pendingTransportIntent = nil
            self.publishState()
        }
    }

    private func clearPendingIntent() {
        pendingTransportIntent = nil
        intentTimeoutTask?.cancel()
        intentTimeoutTask = nil
    }

    private func reconcilePendingIntent(with sample: ListeningPlaybackSample) {
        guard let intent = pendingTransportIntent else { return }

        if intent.target.matches(sample) {
            clearPendingIntent()
            return
        }

        let age = sample.observedAt.timeIntervalSince(intent.issuedAt)
        if age < 0 || age > Self.transportAcknowledgementWindow {
            clearPendingIntent()
        }
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
        stateMachine.handle(.sample(sample))
        reconcilePendingIntent(with: sample)
        publishState()
        transportSampleDidChange(sample)
        ListeningRemoteCommandBridge.shared.update(controller: self, sample: sample)
        try recordEvidence(sample, now: now, handling: evidence)
    }

    private func applyProgress(
        sample: ListeningPlaybackSample,
        now: Date,
        evidence: EvidenceHandling
    ) throws {
        stateMachine.handle(.progress(sample))
        publishState()
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

    private func publishState() {
        let truth = transportState
        if lastPublishedTransportState != truth {
            lastPublishedTransportState = truth
            transportStateDidChange(truth)
        }

        let projected = state
        if lastPublishedState != projected {
            lastPublishedState = projected
            stateDidChange(projected)
        }
    }

    private func startTransportObservation() {
        transportObservationTask?.cancel()
        transportObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await sample in self.service.transportEvents() {
                if Task.isCancelled { return }
                if self.service.failure != nil {
                    self.clearPendingIntent()
                    self.stateMachine.handle(.failed)
                    self.publishState()
                    continue
                }
                do {
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
                guard self.stateMachine.state.isPlaying,
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
        intentTimeoutTask?.cancel()
        intentTimeoutTask = nil
        evidenceFlushTask?.cancel()
        evidenceFlushTask = nil
    }
}

@MainActor
final class ListeningRemoteCommandBridge {
    static let shared = ListeningRemoteCommandBridge()

    private weak var controller: ListeningPlaybackController?
    private var itemsBySongID: [String: ListeningPlaybackItem] = [:]

    private init() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in ListeningRemoteCommandBridge.shared.previous() }
            return .success
        }
    }

    func attach(controller: ListeningPlaybackController, items: [ListeningPlaybackItem]) {
        self.controller = controller
        itemsBySongID = Dictionary(uniqueKeysWithValues: items.map { ($0.songID, $0) })
    }

    func detach(controller: ListeningPlaybackController) {
        guard self.controller === controller else { return }
        self.controller = nil
        itemsBySongID = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func update(
        controller: ListeningPlaybackController,
        sample: ListeningPlaybackSample
    ) {
        guard self.controller === controller,
              let item = itemsBySongID[sample.songID] else { return }
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyExternalContentIdentifier: sample.songID,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: sample.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: sample.isPlaying ? 1.0 : 0.0
        ]
        if let title = item.title { info[MPMediaItemPropertyTitle] = title }
        if let artistName = item.artistName { info[MPMediaItemPropertyArtist] = artistName }
        if let duration = sample.duration ?? item.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func play() {
        guard let controller else { return }
        Task { @MainActor in try? await controller.play() }
    }

    private func pause() {
        try? controller?.pause()
    }

    private func togglePlayPause() {
        guard let controller else { return }
        switch controller.state {
        case .playing:
            try? controller.pause()
        default:
            Task { @MainActor in try? await controller.play() }
        }
    }

    private func next() {
        guard let controller else { return }
        Task { @MainActor in try? await controller.skipToNext() }
    }

    private func previous() {
        guard let controller else { return }
        Task { @MainActor in try? await controller.skipToPrevious() }
    }

    func playForTesting() async throws {
        try await controller?.play()
    }

    func togglePlayPauseForTesting() async throws {
        guard let controller else { return }
        switch controller.state {
        case .playing:
            try controller.pause()
        default:
            try await controller.play()
        }
    }

    func pauseForTesting() throws {
        try controller?.pause()
    }

    func nextForTesting() async throws {
        try await controller?.skipToNext()
    }

    @discardableResult
    func refreshForTesting(now: Date = Date()) throws -> ListeningPlaybackState? {
        try controller?.refresh(now: now)
    }
}

