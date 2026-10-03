import Observation

@MainActor
@Observable
final class FootprintDetailPresentation {
    private(set) var destination: FootprintDetailOverlay?

    var sheet: FootprintDetailOverlay? {
        get { destination?.surface == .sheet ? destination : nil }
        set { update(newValue, surface: .sheet) }
    }

    var fullScreenCover: FootprintDetailOverlay? {
        get { destination?.surface == .fullScreenCover ? destination : nil }
        set { update(newValue, surface: .fullScreenCover) }
    }

    var isShowingDeleteConfirmation: Bool {
        get { destination?.surface == .alert }
        set {
            if newValue {
                present(.deleteConfirmation)
            } else {
                update(nil, surface: .alert)
            }
        }
    }

    func present(_ destination: FootprintDetailOverlay) {
        self.destination = destination
    }

    func openMemory(_ fragment: MemoryFragment, initialIndex: Int = 0) {
        present(fragment.orderedMediaItems.isEmpty
            ? .textMemory(fragment, initialIndex: initialIndex)
            : .mediaMemory(fragment, initialIndex: initialIndex))
    }

    func openShare(_ route: FootprintDetailShareRoute) {
        switch route {
        case .composer: present(.shareComposer)
        case .dispersalCard: present(.dispersalShare)
        case .none: break
        }
    }

    func dismiss() {
        destination = nil
    }

    func isPlaybackActive(sceneIsActive: Bool) -> Bool {
        sceneIsActive && destination == nil
    }

    private func update(_ value: FootprintDetailOverlay?, surface: FootprintDetailOverlay.Surface) {
        if let value {
            present(value)
        } else if destination?.surface == surface {
            dismiss()
        }
    }
}
