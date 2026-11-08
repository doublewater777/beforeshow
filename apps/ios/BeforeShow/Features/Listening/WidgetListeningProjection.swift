import Foundation

/// Projects Listen's session onto the widget. The widget does not choose a disc,
/// a cover, or a playback phase of its own. With no session it offers 「今天这张」,
/// and carries the next day's so the widget can turn over at local midnight.
enum WidgetListeningProjection {
    struct Input {
        var showID: UUID?
        var showName: String
        var seatedDisc: ListeningDisc?
        var track: ListeningDiscTrack?
        var playerPhase: ListeningPlayerPhase
        var playPauseAction: ListeningPlayPauseAction
        var todayDisc: ListeningDisc?
        var todayCanLoad: Bool
        var tomorrowDisc: ListeningDisc? = nil
        var tomorrowStartsAt: Date? = nil
    }

    static func make(_ input: Input) -> WidgetListeningSnapshot {
        if let disc = input.seatedDisc {
            return session(input, disc: disc)
        }
        if let disc = input.todayDisc, input.todayCanLoad {
            var today = snapshot(input, disc: disc, track: nil, phase: .idle, control: .play, hasSession: false)
            if let next = input.tomorrowDisc, let startsAt = input.tomorrowStartsAt {
                today.nextDisc = WidgetListeningNextDisc(
                    startsAt: startsAt,
                    artistName: next.artistNames.first,
                    discTitle: next.title,
                    coverImageURL: next.artworkURL?.absoluteString,
                    trackCount: next.tracks.count
                )
            }
            return today
        }
        return snapshot(
            input,
            disc: nil,
            track: nil,
            phase: .unavailable,
            control: .openListen,
            hasSession: false
        )
    }

    private static func session(_ input: Input, disc: ListeningDisc) -> WidgetListeningSnapshot {
        let phase = phase(for: input.playerPhase, action: input.playPauseAction)
        let control: WidgetListeningControl = switch input.playPauseAction {
        case .disabled: .openListen
        case .pause: .pause
        case .play: .play
        }
        return snapshot(input, disc: disc, track: input.track, phase: phase, control: control, hasSession: true)
    }

    private static func phase(
        for playerPhase: ListeningPlayerPhase,
        action: ListeningPlayPauseAction
    ) -> WidgetListeningPhase {
        switch playerPhase {
        case .preparing: return .preparing
        case .waiting: return .waiting
        case .playing: return .playing
        case .seeking: return .seeking
        case .paused: return .paused
        case .interrupted: return .interrupted
        case .failed: return .failed
        case .stopped, .noDisc:
            return action == .disabled ? .unavailable : .paused
        }
    }

    private static func snapshot(
        _ input: Input,
        disc: ListeningDisc?,
        track: ListeningDiscTrack?,
        phase: WidgetListeningPhase,
        control: WidgetListeningControl,
        hasSession: Bool
    ) -> WidgetListeningSnapshot {
        WidgetListeningSnapshot(
            showID: input.showID,
            showName: input.showName,
            artistName: track?.artistName ?? disc?.artistNames.first,
            discTitle: disc?.title,
            trackTitle: track?.title,
            coverImageURL: disc?.artworkURL?.absoluteString,
            trackCount: disc?.tracks.count,
            phase: phase,
            control: control,
            hasSession: hasSession,
            generatedAt: Date()
        )
    }
}
