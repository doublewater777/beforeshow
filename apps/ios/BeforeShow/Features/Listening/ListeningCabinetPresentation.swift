import Foundation

/// Sheet dismissal grants loading; browsing does not mutate playback.
struct ListeningCabinetPresentation {
    enum Phase { case idle, browsing, dismissing }
    private(set) var phase: Phase = .idle
    private var selection: ListeningDisc?

    var isPresented: Bool { phase == .browsing }

    mutating func present() {
        guard phase == .idle else { return }
        phase = .browsing
    }

    mutating func select(_ disc: ListeningDisc) {
        guard phase == .browsing else { return }
        selection = disc
        phase = .dismissing
    }

    mutating func dismiss() {
        guard phase == .browsing else { return }
        phase = .dismissing
    }

    mutating func completeDismissal() -> ListeningDisc? {
        guard phase == .dismissing else { return nil }
        defer { cancel() }
        return selection
    }

    mutating func cancel() {
        selection = nil
        phase = .idle
    }
}
