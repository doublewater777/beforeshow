import SwiftUI

/// Light follows the mechanism and unified playback presentation, including startup waiting.
enum ListeningAtmospherePhase: Equatable {
    case resting, placing, playing

    init(isPlacing: Bool, isPlaying: Bool) {
        if isPlacing {
            self = .placing
        } else {
            self = isPlaying ? .playing : .resting
        }
    }

    @MainActor init(room: ListeningRoomCoordinator) {
        self = room.atmospherePhase
    }

    var color: Color {
        switch self {
        case .resting: BSListeningTokens.restingLight
        case .placing: BSListeningTokens.placingLight
        case .playing: BSColor.Stage.accent
        }
    }
}
