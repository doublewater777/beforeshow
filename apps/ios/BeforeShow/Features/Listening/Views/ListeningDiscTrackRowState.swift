import SwiftUI

enum ListeningDiscTrackRowState: Equatable {
    case normal
    case preparing
    case playing
    case paused
    case unavailable

    var isActive: Bool {
        switch self {
        case .preparing, .playing, .paused:
            true
        case .normal, .unavailable:
            false
        }
    }
}

