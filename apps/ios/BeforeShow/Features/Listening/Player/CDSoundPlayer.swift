import AVFoundation

/// Mechanical foley for the CD machine, keyed by transition name. Disc seating
/// speaks twice: "seat" clicks the disc onto the spindle, then "read" supplies
/// the spin-up / laser-seek texture. Track preparation may still request the
/// legacy "read" cue, but that request is intentionally silent so changing
/// tracks on the same disc does not replay the loading sound. Panel buttons
/// use tactile haptics rather than audio so transport commands never interrupt
/// music. Everything else — button, lid, insert, remove, release, store —
/// stays silent; its files remain in Resources/Sounds as `cd-<name>.caf`.
/// Sounds mix with music playback and never duck it; when no music plays the
/// ambient session keeps them on the silent switch.
@MainActor final class CDSoundPlayer {
    static let shared = CDSoundPlayer()

    /// Output trim per enabled audio asset so effects sit under the music.
    private static let gains: [String: Float] = [
        "seat": 0.65,
        "read": 0.3,
    ]

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

    /// Pure routing kept internal so tests can lock down when the read sound is
    /// allowed to fire without touching AVAudioSession or bundle resources.
    static func audioCues(for transition: String) -> [String] {
        switch transition {
        case "seat":
            return ["seat", "read"]
        case "button", "read":
            return []
        default:
            return []
        }
    }

    /// Create and prepare every enabled player up front; the first lazy load
    /// otherwise lands noticeably after the first button press.
    func warmup() {
        for transition in Self.gains.keys { _ = player(for: transition) }
    }

    func play(_ transition: String) {
        for cue in Self.audioCues(for: transition) {
            guard let player = player(for: cue) else { continue }
            player.currentTime = 0
            player.play()
        }
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
