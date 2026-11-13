import SwiftData
import SwiftUI

/// Holds the one shared show waiting until the root can open it.
@MainActor
@Observable
final class SharedShowInbox {
    static let shared = SharedShowInbox()

    struct Pending: Equatable {
        let token: String
        let draft: ShowDraft
    }

    var pending: Pending?
    @ObservationIgnored private var lastReceived: (token: String, at: Date)?

    /// `true` for any show link, whether or not it decodes; such links never fall through to other routes.
    @discardableResult
    func receive(_ url: URL, now: Date = .now) -> Bool {
        guard let token = ShowShareLink.token(in: url) else { return false }
        // The scene delegate and SwiftUI may both deliver the same open; a later scan of the same code still counts.
        if let last = lastReceived, last.token == token, now.timeIntervalSince(last.at) < 3 { return true }
        lastReceived = (token, now)
        if let draft = ShowShareLink.draft(from: url) {
            pending = Pending(token: token, draft: draft)
        }
        return true
    }
}

enum SharedShowImportOutcome: Equatable {
    case deferred
    case alreadyAdded
    case prefill(ShowDraft)
}

@MainActor
enum SharedShowImportRouting {
    static func resolve(_ draft: ShowDraft, isOnboardingActive: Bool, in modelContext: ModelContext) throws -> SharedShowImportOutcome {
        guard !isOnboardingActive else { return .deferred }
        let candidate = try draft.makeShow()
        let shows = try modelContext.fetch(FetchDescriptor<Show>())
        return ShowDuplicateMatcher.firstDuplicate(of: candidate, in: shows) == nil ? .prefill(draft) : .alreadyAdded
    }
}

/// Opens a scanned show once the user is past onboarding: add-show prefilled, or one toast when the show is
/// already here. A show that can't be built from the link is dropped silently.
struct SharedShowImportHost: View {
    let isOnboardingActive: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var inbox = SharedShowInbox.shared
    @State private var prefilled: Prefilled?
    @State private var toast: BSToastPayload?

    private struct Prefilled: Identifiable {
        let id = UUID()
        let draft: ShowDraft
    }

    private struct TaskKey: Equatable {
        let pending: SharedShowInbox.Pending?
        let isOnboardingActive: Bool
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .bsToastOverlay(toast)
            .sheet(item: $prefilled) { item in
                AddShowCoordinatorSheet(prefilledDraft: item.draft)
            }
            .task(id: TaskKey(pending: inbox.pending, isOnboardingActive: isOnboardingActive)) {
                handlePending()
            }
    }

    private func handlePending() {
        guard let pending = inbox.pending, prefilled == nil else { return }
        let outcome = try? SharedShowImportRouting.resolve(pending.draft, isOnboardingActive: isOnboardingActive, in: modelContext)
        switch outcome {
        case .deferred:
            return
        case .alreadyAdded:
            showToast(BSLocalization.text("这场已经在 BeforeShow 里了"))
        case .prefill(let draft):
            prefilled = Prefilled(draft: draft)
        case nil:
            break
        }
        inbox.pending = nil
    }

    private func showToast(_ message: String) {
        let payload = BSToastPayload(tone: .neutral, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            if toast == payload { toast = nil }
        }
    }
}
