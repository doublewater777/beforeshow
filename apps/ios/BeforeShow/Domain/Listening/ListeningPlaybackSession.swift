import Foundation

/// Owns command acknowledgement and observed transport transitions. Presentation
/// and listening evidence never rewrite the transport state in this reducer.
struct ListeningPlaybackSession {
    private var transport = ListeningPlaybackStateMachine()
    private var intent: ListeningPlaybackTransportTarget?
    private var pendingIntent: ListeningPlaybackTransportTarget?
    private var hasNewCommandDuringInterruption = false

    var snapshot: ListeningPlaybackSnapshot {
        ListeningPlaybackSnapshot(state: transport.state, intent: intent, pendingIntent: pendingIntent)
    }

    mutating func prepare(source: ListeningPlaybackSource, intent: ListeningPlaybackTransportTarget?) {
        transport.handle(.prepareStarted(source: source))
        self.intent = intent
        pendingIntent = intent
        hasNewCommandDuringInterruption = false
    }

    mutating func request(_ intent: ListeningPlaybackTransportTarget) {
        self.intent = intent
        pendingIntent = intent
        if case .interrupted = transport.state {
            hasNewCommandDuringInterruption = true
        }
    }

    mutating func receive(_ sample: ListeningPlaybackSample) {
        let previousState = transport.state
        transport.handle(.sample(sample))
        defer {
            if sample.phase != .interrupted {
                hasNewCommandDuringInterruption = false
            }
        }

        if sample.hasEnded {
            intent = nil
            pendingIntent = nil
            return
        }

        // Ending an interruption cancels the old resume desire, including a Play
        // that never started. A fresh user command still waits for acknowledgement.
        if case .interrupted = previousState,
           !hasNewCommandDuringInterruption,
           sample.phase.satisfiesPauseIntent {
            intent = .paused
            pendingIntent = nil
            return
        }

        if let pendingIntent {
            if pendingIntent.matches(sample) {
                self.pendingIntent = nil
            }
            return
        }

        switch sample.phase {
        case .playing, .waiting, .seeking:
            intent = .playing
        case .paused, .stopped:
            switch previousState {
            case .waiting, .playing, .seeking, .paused, .interrupted:
                intent = .paused
            case .idle, .preparing, .ready, .finished, .failed:
                break
            }
        case .interrupted:
            // Interruption does not itself cancel the user's resume desire.
            break
        }
    }

    mutating func progress(_ sample: ListeningPlaybackSample) {
        transport.handle(.progress(sample))
    }

    mutating func fail() {
        transport.handle(.failed)
        intent = nil
        pendingIntent = nil
        hasNewCommandDuringInterruption = false
    }

    mutating func reset() {
        self = Self()
    }
}
