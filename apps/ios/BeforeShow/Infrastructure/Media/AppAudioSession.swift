import AVFoundation

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// muted, so the app stays on `ambient` + `mixWithOthers` until the user explicitly
/// asks to hear one. Views that intentionally play sound switch to `playback` while
/// they are on screen.
enum AppAudioSession {
    static func configureAmbient() {
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    static func configureSoundPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    static func configureMusicPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }
}
