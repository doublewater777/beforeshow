import AVKit
import SwiftUI
import UIKit

// MARK: - Shared review flow

/// Read/edit/delete flow shared by the memory timeline and the read-only footprint detail.
/// Creation stays owned by `MemoryFragmentsView`.
struct MemoryFragmentReviewView: View {
    let showID: UUID
    let fragment: MemoryFragment
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editorLaunch: MemoryEditorLaunch?
    @State private var deleteConfirmationTarget: MemoryFragment?
    @State private var toast: BSToastPayload?

    var body: some View {
        Group {
            if fragment.orderedMediaItems.isEmpty {
                MemoryTextFragmentViewer(
                    fragment: fragment,
                    onEdit: { presentEditorAfterManagementDismisses() },
                    onDelete: { presentDeleteAfterManagementDismisses() }
                )
            } else {
                MemoryMediaViewer(
                    fragment: fragment,
                    initialIndex: initialIndex,
                    onEdit: { presentEditorAfterManagementDismisses() },
                    onDelete: { presentDeleteAfterManagementDismisses() }
                )
            }
        }
        .bsToastOverlay(toast, bottomPadding: 36)
        .fullScreenCover(item: $editorLaunch) { launch in
            MemoryUnifiedEditorView(
                launch: launch,
                onSaveCreate: { _, _, _ in },
                onSaveEdit: { fragment, fullOrder, caption, removedIDs, additions, draftID in
                    try await MemoryFragmentEditCoordinator.save(
                        fragment,
                        showID: showID,
                        fullOrder: fullOrder,
                        caption: caption,
                        removedIDs: removedIDs,
                        additions: additions,
                        draftID: draftID,
                        modelContext: modelContext
                    )
                    presentToast(.success, "已保存修改")
                }
            )
        }
        .alert(
            DangerConfirmation.deleteMemory.title,
            isPresented: Binding(
                get: { deleteConfirmationTarget != nil },
                set: { if !$0 { deleteConfirmationTarget = nil } }
            ),
            presenting: deleteConfirmationTarget
        ) { target in
            Button(DangerConfirmation.deleteMemory.confirmTitle, role: .destructive) {
                deleteConfirmationTarget = nil
                delete(target)
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: { _ in
            Text(DangerConfirmation.deleteMemory.message)
        }
        .preferredColorScheme(.dark)
    }

    private func presentEditorAfterManagementDismisses() {
        editorLaunch = MemoryEditorLaunch(kind: .edit(fragment))
    }

    private func presentDeleteAfterManagementDismisses() {
        deleteConfirmationTarget = fragment
    }

    private func delete(_ fragment: MemoryFragment) {
        let fragmentID = fragment.id
        modelContext.delete(fragment)
        do {
            try modelContext.save()
            Task {
                try? await MemoryFragmentMediaStore.shared.deleteFragment(
                    showID: showID,
                    fragmentID: fragmentID
                )
            }
            dismiss()
        } catch {
            modelContext.rollback()
            presentToast(.failure, "删除失败，请重试")
        }
    }

    private func presentToast(_ tone: BSToastTone, _ message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toast == payload { toast = nil }
        }
    }
}

private struct MemoryTextFragmentViewer: View {
    let fragment: MemoryFragment
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.Stage.foreground)
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                            .background(BSColor.Stage.surfaceRaised, in: Circle())
                            .overlay(Circle().stroke(BSColor.Stage.border))
                   }
                   Spacer()
                    Text(BSLocalization.text("记忆碎片"))
                       .font(BSFont.headline)
                       .foregroundColor(BSColor.Stage.foreground)
                   Spacer()
                   Menu {
                        Button(BSLocalization.text("编辑记忆"), action: onEdit)
                        Button(BSLocalization.text("删除这条记忆"), role: .destructive, action: onDelete)
                   } label: {
                        Image(systemName: "ellipsis")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.Stage.foreground)
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                            .background(BSColor.Stage.surfaceRaised, in: Circle())
                            .overlay(Circle().stroke(BSColor.Stage.border))
                    }
                    .accessibilityLabel("管理这条记忆")
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)

                VStack(alignment: .leading, spacing: BSSpacing.roomy) {
                    Image(systemName: "quote.opening")
                        .font(BSFont.V3.title2.weight(.light))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(fragment.text ?? "")
                        .font(BSFont.V3.title2.weight(.regular))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineSpacing(BSSpacing.sm)
                    Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BSSpacing.roomy)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
                .padding(BSSpacing.roomy)

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(BSNavigationBackSwipeRestorer(onBack: { dismiss() }))
    }
}

// MARK: - Viewer

private struct MemoryMediaInteractionSurface: View {
    let kind: MemoryMediaKind
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isShowingActions = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .onLongPressGesture(minimumDuration: 0.4) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingActions = true
            }
            .sheet(isPresented: $isShowingActions) {
                MemoryMediaActionsSheet(
                    onEdit: {
                        isShowingActions = false
                        Task { @MainActor in
                            await Task.yield()
                            onEdit()
                        }
                    },
                    onDelete: {
                        isShowingActions = false
                        Task { @MainActor in
                            await Task.yield()
                            onDelete()
                        }
                    }
                )
            }
            .accessibilityLabel(kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片"))
            .accessibilityHint(BSLocalization.text("轻点关闭，长按管理"))
            .accessibilityAction(named: BSLocalization.text("关闭"), onDismiss)
            .accessibilityAction(named: BSLocalization.text("编辑记忆"), onEdit)
            .accessibilityAction(named: BSLocalization.text("删除这条记忆"), onDelete)
    }
}

struct MemoryMediaViewer: View {
    let fragment: MemoryFragment
    let initialIndex: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(
        fragment: MemoryFragment,
        initialIndex: Int,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.fragment = fragment
        self.initialIndex = initialIndex
        self.onEdit = onEdit
        self.onDelete = onDelete
        _index = State(initialValue: max(0, min(initialIndex, max(0, fragment.orderedMediaItems.count - 1))))
    }

    private var items: [MemoryMediaItem] { fragment.orderedMediaItems }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                    ZStack {
                        mediaPage(item: item, isActive: itemIndex == index)
                        MemoryMediaInteractionSurface(
                            kind: item.kind,
                            onDismiss: { dismiss() },
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }
                    .tag(itemIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        // The viewer plays video with sound, so it needs `playback`; restore the
        // ambient policy on exit so covers stay non-interrupting.
        .onAppear { AppAudioSession.configureSoundPlayback() }
        .onDisappear { AppAudioSession.configureAmbient() }
    }

    @ViewBuilder
    private func mediaPage(item: MemoryMediaItem, isActive: Bool) -> some View {
        if item.kind == .video {
            MemoryViewerVideoPage(
                url: MemoryMediaLocation.applicationSupport().url(for: item.relativePath),
                isActive: isActive
            )
        } else {
            MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                .scaledToFit()
        }
    }
}
