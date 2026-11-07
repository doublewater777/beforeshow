import AVFoundation

/// Short foley for the Footprints rooms. Effects ride the app's ambient
/// session like the CD machine's, so they mix with music and follow the
/// silent switch; they never lease playback.
final class FootprintSoundPlayer: @unchecked Sendable {
    enum Cue: String, CaseIterable {
        case neon
        case clink
        case breath
        case tear

        var gain: Float {
            switch self {
            case .tear: return 0.5
            case .neon: return 0.35
            case .clink: return 0.5
            case .breath: return 0.55
            }
        }
    }

    static let shared = FootprintSoundPlayer()

    // Every player access is confined to AppAudioSession.workQueue.
    private var players: [Cue: AVAudioPlayer] = [:]

    private init() {}

    func play(_ cue: Cue) {
        AppAudioSession.workQueue.async { [self] in
            guard let player = player(for: cue) else { return }
            player.volume = cue.gain
            player.currentTime = 0
            player.play()
        }
    }

    private func player(for cue: Cue) -> AVAudioPlayer? {
        dispatchPrecondition(condition: .onQueue(AppAudioSession.workQueue))
        if let cached = players[cue] { return cached }
        guard let url = Bundle.main.url(forResource: "footprint-\(cue.rawValue)", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[cue] = player
        return player
    }
}
