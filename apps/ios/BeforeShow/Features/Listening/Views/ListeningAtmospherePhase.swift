import SwiftUI

/// The room light follows playback.
enum ListeningAtmospherePhase: Equatable {
    case resting, playing

    init(isPlaying: Bool) {
        self = isPlaying ? .playing : .resting
    }

    var color: Color {
        switch self {
        case .resting: BSListeningTokens.restingLight
        case .playing: BSColor.Stage.accent
        }
    }
}
