import Foundation

/// One publication carries transport truth and command intent together.
struct ListeningPlaybackSnapshot: Equatable, Sendable {
    let state: ListeningPlaybackState
    let intent: ListeningPlaybackTransportTarget?
    let pendingIntent: ListeningPlaybackTransportTarget?

    init(
        state: ListeningPlaybackState = .idle,
        intent: ListeningPlaybackTransportTarget? = nil,
        pendingIntent: ListeningPlaybackTransportTarget? = nil
    ) {
        self.state = state
        self.intent = intent
        self.pendingIntent = pendingIntent
    }

    var wantsPlayback: Bool {
        switch intent {
        case .playing: true
        case .paused: false
        case nil: state.isPlaybackActive
        }
    }

    var source: ListeningPlaybackSource? {
        switch state {
        case let .preparing(source): source
        case let .ready(_, source, _, _),
             let .waiting(_, source, _, _),
             let .playing(_, source, _, _),
             let .seeking(_, source, _, _),
             let .paused(_, source, _, _),
             let .interrupted(_, source, _, _),
             let .finished(_, source, _):
            source
        case .idle, .failed:
            nil
        }
    }
}
