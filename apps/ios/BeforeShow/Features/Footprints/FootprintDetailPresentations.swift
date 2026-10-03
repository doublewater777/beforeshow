import SwiftUI

struct FootprintDetailPresentations: ViewModifier {
    @Bindable var presentation: FootprintDetailPresentation
    let show: Show
    let identity: () -> FootprintDetailIdentity
    let shareMaterials: () -> [FootprintShareMaterial]
    let onDetailVisibilityChange: (Bool) -> Void
    let onApplyDraft: (ShowDraft) async throws -> Void
    let onCommitCeremony: (Int?, String?) async throws -> Void
    let onShareSaved: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentation.sheet) { destination in
                destinationContent(destination)
            }
            .fullScreenCover(item: $presentation.fullScreenCover) { destination in
                destinationContent(destination)
            }
            .alert(
                DangerConfirmation.deleteShow.title,
                isPresented: $presentation.isShowingDeleteConfirmation
            ) {
                Button(DangerConfirmation.deleteShow.confirmTitle, role: .destructive, action: onDelete)
                Button(BSLocalization.text("取消"), role: .cancel) {}
            } message: {
                Text(DangerConfirmation.deleteShow.message)
            }
    }

    @ViewBuilder
    private func destinationContent(_ destination: FootprintDetailOverlay) -> some View {
        switch destination {
        case .mediaMemory(let fragment, let initialIndex):
            MemoryFragmentReviewView(showID: show.id, fragment: fragment, initialIndex: initialIndex)
        case .textMemory(let fragment, let initialIndex):
            MemoryFragmentReviewView(showID: show.id, fragment: fragment, initialIndex: initialIndex)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(BSColor.Stage.background)
                .preferredColorScheme(.dark)
        case .asset(let kind):
            ShowAssetSheet(
                showID: show.id,
                showName: show.name,
                kind: kind,
                onDetailVisibilityChange: onDetailVisibilityChange,
                keepsParentDetailHidden: true
            )
        case .memoryPage:
            MemoryFragmentsSheet(show: show)
        case .editor:
            ShowDraftEditorView(
                title: BSLocalization.text("编辑现场"),
                draft: ShowDraft(show: show),
                saveTitle: BSLocalization.text("保存"),
                statusPillText: CurrentShowSession().phase(for: show, now: Date()).statusText,
                isPostponed: show.changeStatus == .postponed,
                onSave: onApplyDraft
            )
        case .shareComposer:
            FootprintShareComposerView(
                show: show,
                identity: identity(),
                materials: shareMaterials(),
                onClose: presentation.dismiss
            )
        case .dispersalShare:
            DispersalCeremonyShareSheet(
                show: show,
                identity: identity(),
                rating: show.rating,
                note: show.closingNote ?? "",
                onSaved: onShareSaved
            )
            .presentationDetents([.large])
            .presentationCornerRadius(26)
            .presentationDragIndicator(.visible)
        case .ceremonyEditor:
            DispersalCeremonySheet(
                show: show,
                identity: identity(),
                initialStep: .combined,
                headerTitle: BSLocalization.text("散场评价"),
                presentsShareAfterCommit: false,
                onCommit: onCommitCeremony
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(BSColor.Stage.background)
            .preferredColorScheme(.dark)
        case .deleteConfirmation:
            EmptyView()
        }
    }
}
