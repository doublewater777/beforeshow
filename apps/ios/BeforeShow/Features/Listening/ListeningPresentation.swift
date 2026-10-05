import SwiftUI

// Page state is independent of the physical mechanism and transport state.
enum ListeningPresentation: Equatable {
    case noCurrentShow, loading, needsAuthorization, noConnectedArtists
    case loadingCatalog, ready, cachedWithError, fatalUnavailable

    static func resolve(hasShow: Bool, authorized: Bool, connected: Bool, hasSongs: Bool,
                        loading: Bool, failed: Bool, accessResolved: Bool = true) -> Self {
        guard hasShow else { return .noCurrentShow }
        if hasSongs { return failed ? .cachedWithError : .ready }
        if !accessResolved { return .loading }
        if !authorized { return .needsAuthorization }
        if !connected { return .noConnectedArtists }
        if loading { return .loadingCatalog }
        return .fatalUnavailable
    }
}

struct ListeningWantsLivePresentation: Equatable {
    let selected: Bool
    let mutable: Bool
    var label: String { mutable ? "想现场听" : "开场前想现场听" }
    var symbol: String { selected ? "heart.fill" : "heart" }
}

enum ListeningDiscDetailTrackAction: Equatable {
    case selectTrack
    case togglePlayback

    static func resolve(
        isLoaded: Bool,
        isCurrentTrack: Bool,
        player: ListeningPlayerPresentation
    ) -> Self {
        guard isLoaded, isCurrentTrack, player.canPlayPause else {
            return .selectTrack
        }

        switch player.phase {
        case .waiting, .playing, .seeking, .paused, .interrupted:
            return .togglePlayback
        case .noDisc, .preparing, .stopped, .finished, .failed:
            return .selectTrack
        }
    }
}
