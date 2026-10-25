import AVFoundation

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// always muted, so the app stays on `ambient` + `mixWithOthers` by default.
/// An owner that intentionally plays sound leases `playback` while it may sound.
///
/// Inside the app, owners behave like separate apps do under iOS: one sounds at
/// a time. An owner claims focus right before it sounds, every other owner
/// pauses. The focus mechanism never auto-resumes; a completed timetable preview
/// may explicitly restore the listening session it interrupted.
@MainActor
enum AppAudioSession {
    enum Owner: Hashable {
        case listening
        case timetablePreview
        case memoryVideo
    }

    /// Posted synchronously on the main thread; `object` is the claiming `Owner`.
    static let focusDidChange = Notification.Name("AppAudioSession.focusDidChange")

    private static var leases: Set<Owner> = []

    // Session changes and short sound effects share one queue so configuration
    // always precedes playback without waiting for audio hardware on the UI thread.
    nonisolated static let workQueue = DispatchQueue(label: "BeforeShow.audio", qos: .utility)

    static var currentCategory: AVAudioSession.Category {
        AVAudioSession.sharedInstance().category
    }

    /// Applies the policy for the current leases, e.g. the ambient default at launch.
    static func applyPolicy() {
        apply()
    }

    static func lease(_ owner: Owner) {
        leases.insert(owner)
        apply()
    }

    static func release(_ owner: Owner) {
        leases.remove(owner)
        apply()
    }

    /// `owner` is about to sound; every other owner pauses before this returns.
    static func claimFocus(_ owner: Owner) {
        NotificationCenter.default.post(name: focusDidChange, object: owner)
    }

    /// Whether a `focusDidChange` notification takes focus away from `owner`.
    nonisolated static func takesFocus(_ notification: Notification, from owner: Owner) -> Bool {
        guard let claimant = notification.object as? Owner else { return false }
        return claimant != owner
    }

    /// Runs `pause` whenever another owner claims focus. Keep the token for removal.
    static func observeFocusLoss(
        of owner: Owner,
        pause: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: focusDidChange, object: nil, queue: nil) { notification in
            guard takesFocus(notification, from: owner) else { return }
            MainActor.assumeIsolated { pause() }
        }
    }

    static func resetForTests() {
        leases = []
        apply()
    }

    static func waitForPendingOperations() async {
        await withCheckedContinuation { continuation in
            workQueue.async { continuation.resume() }
        }
    }

    private static func apply() {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
        if !leases.isDisjoint(with: [.listening, .timetablePreview]) {
            category = .playback
            mode = .default
            options = []
        } else if leases.contains(.memoryVideo) {
            category = .playback
            mode = .moviePlayback
            options = []
        } else {
            category = .ambient
            mode = .default
            options = [.mixWithOthers]
        }

        workQueue.async {
            let session = AVAudioSession.sharedInstance()
            // Releasing another owner must not reconfigure an unchanged session.
            guard session.category != category || session.mode != mode
                || session.categoryOptions != options else { return }
            try? session.setCategory(category, mode: mode, options: options)
        }
    }
}
