import AVFoundation

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// muted, so the app stays on `ambient` + `mixWithOthers` until the user explicitly
/// asks to hear one. Views that intentionally play sound switch to `playback` while
/// they are on screen.
@MainActor
enum AppAudioSession {
    enum Owner: Equatable {
        case listening
        case sound
    }

    private static var owners: Set<Owner> = []

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

    private static func acquire(_ owner: Owner) {
        owners.insert(owner)
        apply()
    }

    private static func release(_ owner: Owner) {
        owners.remove(owner)
        apply()
    }

    private static func apply() {
        let session = AVAudioSession.sharedInstance()
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

        // Resuming music or releasing another owner's audio must not reconfigure
        // an unchanged session. The players activate it when playback starts;
        // synchronous setActive here blocks the main actor on every resume.
        guard session.category != category || session.mode != mode
            || session.categoryOptions != options else { return }
        try? session.setCategory(category, mode: mode, options: options)
    }
}
