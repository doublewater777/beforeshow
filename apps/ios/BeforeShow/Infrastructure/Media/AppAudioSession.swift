import AVFoundation

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// always muted, so the app stays on `ambient` + `mixWithOthers` by default.
/// Views that intentionally play sound switch to `playback` while they are on screen.
@MainActor
enum AppAudioSession {
    enum Owner: Equatable {
        case listening
        case sound
    }

    private static var owners: Set<Owner> = []

    // Session changes and short sound effects share one queue so configuration
    // always precedes playback without waiting for audio hardware on the UI thread.
    nonisolated static let workQueue = DispatchQueue(label: "BeforeShow.audio", qos: .utility)

    static var currentCategory: AVAudioSession.Category {
        AVAudioSession.sharedInstance().category
    }

    static func configureAmbient() {
        release(.sound)
    }

    static func configureSoundPlayback() {
        acquire(.sound)
    }

    static func configureMusicPlayback() {
        acquire(.listening)
    }

    static func releaseMusicPlayback() {
        release(.listening)
    }

    static func resetForTests() {
        owners = []
        apply()
    }

    static func waitForPendingOperations() async {
        await withCheckedContinuation { continuation in
            workQueue.async { continuation.resume() }
        }
    }

    private static func acquire(_ owner: Owner) {
        owners.insert(owner)
        apply()
    }

    private static func release(_ owner: Owner) {
        owners.remove(owner)
        apply()
    }

    private static func apply() {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
        if owners.contains(.listening) {
            category = .playback
            mode = .default
            options = []
        } else if owners.contains(.sound) {
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
