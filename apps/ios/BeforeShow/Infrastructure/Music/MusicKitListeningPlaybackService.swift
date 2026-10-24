import Foundation
import Combine
import Observation
import AVFoundation
@preconcurrency import MusicKit

/// Full-catalog playback on `ApplicationMusicPlayer`, the way Apple's MusicKit
/// samples drive it: one shared player, one queue per loaded disc, state read
/// straight from the player. Lock Screen and Control Center belong to the system.
///
/// MusicKit reports `.interrupted` but never resumes by itself, so this
/// service keeps the user's play intent across the interruption and asks the
/// player to resume only when the system recommends it.
@MainActor
@Observable
final class MusicKitListeningPlaybackService: ListeningPlaybackServicing {
    let source = ListeningPlaybackSource.fullCatalog
    private let player: ApplicationMusicPlayer
    private var songsByID: [String: Song] = [:]
    private var durationBySongID: [String: TimeInterval] = [:]
    private(set) var queuedSongIDs: [String] = []
    private var playerRevision = 0
    private var playbackIntent = ListeningPlaybackIntent()
    @ObservationIgnored private var playerObservers: [AnyCancellable] = []
    @ObservationIgnored private var audioObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var focusObserver: NSObjectProtocol?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var pauseConfirmationTask: Task<Void, Never>?

    init(player: ApplicationMusicPlayer = .shared) {
        self.player = player
        observePlayer()
        observeAudioSession()
        focusObserver = AppAudioSession.observeFocusLoss(of: .listening) { [weak self] in
            self?.pause()
        }
    }

    private func observePlayer() {
        playerObservers = [player.state.objectWillChange, player.queue.objectWillChange].map { changes in
            changes.sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.trackPlaybackIntent()
                    self.playerRevision &+= 1
                }
            }
        }
    }

    /// A pause reported by MusicKit may be the system taking the session for
    /// an interruption, or the user pausing from the Lock Screen. Wait for the
    /// interruption notification to settle it before clearing the intent.
    private func trackPlaybackIntent() {
        let phase = self.phase
        playbackIntent.playerDidChange(to: phase)
        guard phase == .paused else {
            pauseConfirmationTask?.cancel()
            return
        }
        pauseConfirmationTask?.cancel()
        pauseConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            guard self.phase == .paused else { return }
            self.playbackIntent.confirmedPause()
        }
    }

    isolated deinit {
        resumeTask?.cancel()
        pauseConfirmationTask?.cancel()
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
    }

    var phase: ListeningPlaybackTransportPhase {
        _ = playerRevision
        return switch player.state.playbackStatus {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        case .interrupted: .interrupted
        case .seekingForward, .seekingBackward: .seeking
        @unknown default: .stopped
        }
    }

    var currentSongID: String? {
        guard !queuedSongIDs.isEmpty else { return nil }
        // A finished queue has no current entry; its last song stays loaded.
        return currentEntrySongID ?? queuedSongIDs.last
    }

    var hasEnded: Bool {
        _ = playerRevision
        guard !queuedSongIDs.isEmpty else { return false }
        let status = player.state.playbackStatus
        guard status == .stopped || status == .paused else { return false }
        guard let songID = currentEntrySongID else { return true }
        // Only the last song can end the queue; a pause near the end of another is a pause.
        guard songID == queuedSongIDs.last else { return false }
        return ListeningPlaybackCompletionPolicy.hasEnded(
            currentTime: currentTime,
            duration: duration(of: songID),
            isPlaying: false
        )
    }

    var failure: ListeningPlaybackError? { nil }

    var currentTime: TimeInterval {
        let time = player.playbackTime
        return time.isFinite ? max(0, time) : 0
    }

    var currentDuration: TimeInterval? {
        currentSongID.flatMap(duration(of:))
    }

    func prefetch(_ items: [ListeningPlaybackItem]) async {
        try? await fetchMissingSongs(items.map(\.songID))
    }

    func load(_ items: [ListeningPlaybackItem], startingAt songID: String?, at time: TimeInterval) async throws {
        guard !items.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        // Loading a queue is not playback; a stale intent from the previous
        // session must not resurrect it when an interruption ends.
        playbackIntent.stopped()
        resumeTask?.cancel()
        pauseConfirmationTask?.cancel()
        try await fetchMissingSongs(items.map(\.songID))
        // Songs the catalog no longer returns are skipped instead of failing the disc.
        let playable = items.filter { songsByID[$0.songID] != nil }
        guard let first = playable.first else {
            throw ListeningPlaybackError.songUnavailable(songID ?? items[0].songID)
        }
        for item in items {
            if let duration = item.duration { durationBySongID[item.songID] = duration }
        }
        let startID = Self.startingSongID(requested: songID, items: items, playable: playable) ?? first.songID
        let songs = playable.compactMap { songsByID[$0.songID] }
        queuedSongIDs = playable.map(\.songID)
        player.state.repeatMode = MusicPlayer.RepeatMode.none
        player.state.shuffleMode = .off
        player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: songsByID[startID])
        observePlayer()
        playerRevision &+= 1
        AppAudioSession.lease(.listening)
        await AppAudioSession.waitForPendingOperations()
        try Task.checkCancellation()
        try await player.prepareToPlay()
        if time > 0 {
            player.playbackTime = time
        }
    }

    func play() async throws {
        playbackIntent.requestedPlay()
        pauseConfirmationTask?.cancel()
        AppAudioSession.lease(.listening)
        await AppAudioSession.waitForPendingOperations()
        try Task.checkCancellation()
        AppAudioSession.claimFocus(.listening)
        try await player.play()
    }

    func pause() {
        playbackIntent.requestedPause()
        resumeTask?.cancel()
        pauseConfirmationTask?.cancel()
        player.pause()
    }

    func skipToNext() async throws {
        try await player.skipToNextEntry()
    }

    func skipToPrevious() async throws {
        try await player.skipToPreviousEntry()
    }

    /// Moves within the loaded queue instead of replacing it.
    func skip(to songID: String) async throws {
        let entry = player.queue.entries.first { entry in
            guard case let .song(song) = entry.item else { return false }
            return song.id.rawValue == songID
        }
        guard queuedSongIDs.contains(songID), let entry else {
            throw ListeningPlaybackError.songUnavailable(songID)
        }
        let continuesPlaying = phase.isActive
        player.queue.currentEntry = entry
        if continuesPlaying, !phase.isActive {
            try await play()
        }
    }

    func stop() {
        playbackIntent.stopped()
        resumeTask?.cancel()
        pauseConfirmationTask?.cancel()
        player.stop()
        queuedSongIDs = []
        AppAudioSession.release(.listening)
    }

    /// MusicKit exposes `.interrupted` but, unlike `AVPlayer`, does not resume
    /// on its own. The app owns the decision, exactly as Apple's interruption
    /// guidance describes for any player.
    private func observeAudioSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
            let options = AVAudioSession.InterruptionOptions(
                rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            let routeDisconnected = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                == AVAudioSession.InterruptionReason.routeDisconnected.rawValue
            MainActor.assumeIsolated {
                self?.handleInterruption(type, options: options, routeDisconnected: routeDisconnected)
            }
        })
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] notification in
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    private func handleInterruption(
        _ type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions,
        routeDisconnected: Bool
    ) {
        switch type {
        case .began:
            resumeTask?.cancel()
            playbackIntent.interruptionBegan()
            // MusicKit already paused the player. Asking it to pause would
            // erase `.interrupted` and with it the reason to resume later.
            if routeDisconnected { pause() }
        case .ended:
            guard playbackIntent.isInterrupted else { return }
            playbackIntent.interruptionEnded()
            guard playbackIntent.shouldResume(
                systemRecommendsResume: options.contains(.shouldResume)
            ) else {
                pause()
                return
            }
            resumeTask = Task { [weak self] in
                guard let self else { return }
                try? await self.play()
            }
        @unknown default:
            break
        }
    }

    private var currentEntrySongID: String? {
        _ = playerRevision
        guard case let .song(song) = player.queue.currentEntry?.item else { return nil }
        return song.id.rawValue
    }

    private func duration(of songID: String) -> TimeInterval? {
        songsByID[songID]?.duration ?? durationBySongID[songID]
    }

    /// The requested song, or the next one the catalog could resolve.
    private static func startingSongID(
        requested: String?,
        items: [ListeningPlaybackItem],
        playable: [ListeningPlaybackItem]
    ) -> String? {
        guard let requested,
              let index = items.firstIndex(where: { $0.songID == requested }) else { return nil }
        let playableIDs = Set(playable.map(\.songID))
        return items[index...].first { playableIDs.contains($0.songID) }?.songID
    }

    private func fetchMissingSongs(_ ids: [String]) async throws {
        var seen = Set<String>()
        let missing = ids.filter { songsByID[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty else { return }
        let batches = stride(from: 0, to: missing.count, by: 25).map {
            Array(missing[$0..<min($0 + 25, missing.count)])
        }
        let fetched = try await withThrowingTaskGroup(of: [Song].self) { group in
            for batch in batches {
                group.addTask {
                    var request = MusicCatalogResourceRequest<Song>(
                        matching: \.id,
                        memberOf: batch.map { MusicItemID($0) }
                    )
                    request.limit = batch.count
                    return Array(try await request.response().items)
                }
            }
            var songs: [Song] = []
            for try await batch in group { songs += batch }
            return songs
        }
        for song in fetched {
            songsByID[song.id.rawValue] = song
        }
    }
}
