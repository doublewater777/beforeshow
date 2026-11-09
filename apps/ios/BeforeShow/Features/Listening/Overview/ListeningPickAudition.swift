import Foundation
import Observation

/// Plays the record you're looking at in 帮我挑一张 from its 30-second previews, on its own
/// player: the deck and the mini player keep what you were listening to until you choose
/// 就听这张. Leaving without choosing picks the interrupted record back up.
@MainActor
@Observable
final class ListeningPickAudition {
    private(set) var discID: String?
    private(set) var isPlaying = false

    @ObservationIgnored private let playback = PreviewListeningPlaybackService(owner: .pickAudition)
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var interrupted: InterruptedListening?
    @ObservationIgnored private var focusObserver: NSObjectProtocol?

    init() {
        focusObserver = AppAudioSession.observeFocusLoss(of: .pickAudition) { [weak self] in
            // Something else started sounding; don't bring the old record back over it.
            self?.isPlaying = false
            self?.interrupted = nil
        }
    }

    func isAuditioning(_ disc: ListeningDisc) -> Bool { discID == disc.id && isPlaying }

    /// The disc's own track order, previews only; nothing playable leaves the room quiet.
    static func items(for disc: ListeningDisc) -> [ListeningPlaybackItem] {
        disc.tracks.filter { $0.previewURL != nil }.map { $0.playbackItem(on: disc) }
    }

    func play(_ disc: ListeningDisc) {
        guard discID != disc.id else { return }
        task?.cancel()
        let items = Self.items(for: disc)
        discID = disc.id
        isPlaying = false
        guard let first = items.first else {
            playback.stop()
            return
        }
        rememberInterruptedListening()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await playback.load(items, startingAt: first.songID, at: 0)
                try Task.checkCancellation()
                try await playback.play()
                try Task.checkCancellation()
                isPlaying = true
            } catch {
                if !Task.isCancelled { isPlaying = false }
            }
        }
    }

    /// `resumeListening` brings back the record the audition interrupted (leaving without choosing).
    func stop(resumeListening: Bool) {
        task?.cancel()
        task = nil
        playback.stop()
        discID = nil
        isPlaying = false
        defer { interrupted = nil }
        if resumeListening { interrupted?.resume() }
    }

    private func rememberInterruptedListening() {
        if interrupted == nil { interrupted = InterruptedListening.capture() }
    }
}
