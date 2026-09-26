import SwiftUI

/// Light follows the mechanism and actual transport, including manual insertion.
enum ListeningAtmospherePhase: Equatable {
    case resting, placing, playing

    @MainActor init(room: ListeningRoomCoordinator) {
        let mechanism = room.mechanism
        if mechanism.isAutomatic || mechanism.position == .removed || mechanism.isOpen {
            self = .placing
        } else {
            self = room.isPlaying ? .playing : .resting
        }
    }

    var color: Color {
        switch self {
        case .resting: BSListeningTokens.restingLight
        case .placing: BSListeningTokens.placingLight
        case .playing: BSColor.Stage.accent
        }
    }

    var opacity: Double {
        switch self {
        case .resting: BSListeningTokens.haloRestingOpacity
        case .placing: BSListeningTokens.haloPlacingOpacity
        case .playing: BSListeningTokens.haloPlayingOpacity
        }
    }

    var scale: CGFloat {
        switch self {
        case .resting: BSListeningTokens.haloRestingScale
        case .placing: BSListeningTokens.haloPlacingScale
        case .playing: 1
        }
    }
}
