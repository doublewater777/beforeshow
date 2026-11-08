import SwiftData
import SwiftUI

/// Handles a link from the retired invite flow once the user is past onboarding:
/// a show already here just gains the inviter as companion (one toast); otherwise the
/// add-show flow opens prefilled. Failures stay silent.
struct LegacyCompanionInviteHost: View {
    let isOnboardingActive: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var inbox = LegacyCompanionInviteInbox.shared
    @State private var prefilledDraft: PrefilledDraft?
    @State private var toast: BSToastPayload?

    private struct PrefilledDraft: Identifiable {
        let id = UUID()
        let draft: ShowDraft
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .bsToastOverlay(toast)
            .sheet(item: $prefilledDraft) { item in
                AddShowCoordinatorSheet(prefilledDraft: item.draft)
            }
            .task(id: TaskKey(token: inbox.pending?.token, isOnboardingActive: isOnboardingActive)) {
                handlePending()
            }
    }

    private struct TaskKey: Equatable {
        let token: String?
        let isOnboardingActive: Bool
    }

    private func handlePending() {
        guard let snapshot = inbox.pending, prefilledDraft == nil else { return }
        let outcome = try? LegacyCompanionInviteRouting.resolve(
            snapshot,
            isOnboardingActive: isOnboardingActive,
            in: modelContext
        )
        switch outcome {
        case .deferred:
            return
        case .addedCompanion(_, let name):
            if let name {
                show(BSLocalization.format("已记下与%@同行", name))
            }
        case .prefillAddShow(let draft):
            prefilledDraft = PrefilledDraft(draft: draft)
        case nil:
            break
        }
        inbox.pending = nil
    }

    private func show(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            if toast == payload { toast = nil }
        }
    }
}
