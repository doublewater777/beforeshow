import SwiftUI

// Page state is independent of the physical mechanism and transport state.
enum ListeningPresentation: Equatable {
    case noCurrentShow, loading, needsAuthorization, noConnectedArtists
    case loadingCatalog, ready, cachedWithError, fatalUnavailable

    static func resolve(hasShow: Bool, authorized: Bool, connected: Bool, hasSongs: Bool,
                        loading: Bool, failed: Bool) -> Self {
        guard hasShow else { return .noCurrentShow }
        if hasSongs { return failed ? .cachedWithError : .ready }
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

extension ListeningFamiliarityTier {
    var localizationKey: String {
        switch self {
        case .firstEncounter: "初次相遇"
        case .newListener: "开始认识"
        case .gettingIntoIt: "渐渐入迷"
        case .familiar: "已经熟悉"
        case .deepListener: "深度乐迷"
        }
    }
}

/// User pause and lifecycle pause have different ownership. No media I/O here.
struct ListeningVisibilityPolicy {
    private(set) var userPaused = false
    private(set) var interrupted = false
    mutating func userPause() { userPaused = true; interrupted = false }
    mutating func userPlay() { userPaused = false; interrupted = false }
    mutating func interrupt(wasPlaying: Bool) { if wasPlaying && !userPaused { interrupted = true } }
    mutating func resumeIfAllowed() -> Bool {
        guard interrupted && !userPaused else { return false }
        interrupted = false
        return true
    }
    static func mustPause(tabVisible: Bool, foreground: Bool, source: ListeningPlaybackSource?) -> Bool {
        !tabVisible || (!foreground && source == .preview)
    }
}
