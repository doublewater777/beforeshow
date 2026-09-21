import Foundation

enum ListeningDeviceStatus {
    case empty, loading, open, ready, reading, playing, paused, error

    var label: String {
        switch self {
        case .empty: BSLocalization.text("无唱片")
        case .loading, .reading: ListeningCopy.text("载入中…")
        case .open, .ready: BSLocalization.text("已就绪")
        case .playing: BSLocalization.text("播放中")
        case .paused: BSLocalization.text("暂停")
        case .error: BSLocalization.text("暂不可播放")
        }
    }
}

extension ListeningRoomCoordinator {
    var deviceStatus: ListeningDeviceStatus {
        if mechanism.isAutomatic { return .loading }
        if !mechanism.hasDisc { return .empty }
        if playbackError != nil { return .error }
        if let track, !trackPresentation(for: track).isPlayable { return .error }
        switch playbackState {
        case .preparing: return .reading
        case .playing: return .playing
        case .paused: return .paused
        case .failed: return .error
        case .idle, .ready, .finished: return .ready
        }
    }
}
