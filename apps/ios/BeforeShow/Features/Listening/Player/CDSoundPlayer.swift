import AVFoundation

/// Mechanical foley for the CD machine, keyed by transition name. Only two
/// moments speak: "seat" (the disc clicks onto the spindle), "read"
/// (spin-up and laser seek while a new track prepares), and "button" (the
/// panel keys). Everything else —
/// lid, insert, remove, release, store — stays silent; its files remain in
/// Resources/Sounds as `cd-<name>.caf`, so re-enabling one is one line here.
/// Sounds mix with music playback and never duck it; when no music plays the
/// ambient session keeps them on the silent switch.
@MainActor final class CDSoundPlayer {
    static let shared = CDSoundPlayer()

    /// Output trim per enabled transition so effects sit under the music.
    /// A transition not listed here is silent.
    private static let gains: [String: Float] = [
        "seat": 0.65,
        "read": 0.3,
        "button": 0.3,
    ]

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

    /// Create and prepare every enabled player up front; the first lazy load
    /// otherwise lands noticeably after the first button press.
    func warmup() {
        for transition in Self.gains.keys { _ = player(for: transition) }
    }

    func play(_ transition: String) {
        guard let player = player(for: transition) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for transition: String) -> AVAudioPlayer? {
        if let cached = players[transition] { return cached }
        guard Self.gains[transition] != nil,
              let url = Bundle.main.url(forResource: "cd-\(transition)", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = Self.gains[transition] ?? 0.5
        player.prepareToPlay()
        players[transition] = player
        return player
    }
}
