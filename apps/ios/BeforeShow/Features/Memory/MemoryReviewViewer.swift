import AVKit
import SwiftData
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
                    BSChromeIconButton(
                        systemName: "xmark",
                        accessibilityLabel: BSLocalization.text("关闭"),
                        action: { dismiss() }
                    )
                    Spacer()
                    Text(BSLocalization.text("记忆碎片"))
                        .font(BSFont.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                    Spacer()
                    Menu {
                        Button(BSLocalization.text("编辑记忆"), action: onEdit)
                        Button(BSLocalization.text("删除这条记忆"), role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: BSLayout.chromeIconSize, weight: .semibold))
                            .foregroundStyle(BSColor.textPrimary)
                            .frame(width: BSLayout.chromeButtonSize, height: BSLayout.chromeButtonSize)
                            .background(Color.white.opacity(0.07), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("管理这条记忆")
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.roomy) {
                        Image(systemName: "quote.opening")
                            .font(BSFont.V3.title2.weight(.light))
                            .foregroundStyle(BSColor.Stage.accent)
                        Text(fragment.text ?? "")
                            .font(BSFont.V3.title2.weight(.regular))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .lineSpacing(BSSpacing.sm)
                        Text(BSDateFormat.dateTime(fragment.createdAt, timeZone: .current))
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BSSpacing.roomy)
                    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
                    .padding(BSSpacing.roomy)
                }

                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Viewer

struct MemoryMediaViewer: View {
    let fragment: MemoryFragment
    let initialIndex: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var isAudioConfigured = false

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
        BSFullscreenImageViewer(pageCount: items.count, currentIndex: $index) { itemIndex in
            mediaPage(item: items[itemIndex], isActive: itemIndex == index && isAudioConfigured)
        }
        .interactiveDismissDisabled()
        // The viewer plays video with sound, so it needs `playback`; restore the
        // ambient policy on exit so covers stay non-interrupting.
        .task {
            guard !Task.isCancelled else { return }
            AppAudioSession.lease(.memoryVideo)
            await AppAudioSession.waitForPendingOperations()
            guard !Task.isCancelled else { return }
            isAudioConfigured = true
        }
        .onDisappear {
            isAudioConfigured = false
            AppAudioSession.release(.memoryVideo)
        }
    }

    @ViewBuilder
    private func mediaPage(item: MemoryMediaItem, isActive: Bool) -> some View {
        let url = MemoryMediaLocation.applicationSupport().url(for: item.relativePath)
        if item.kind == .video {
            ZStack {
                MemoryViewerVideoPage(url: url, isActive: isActive)
                MemoryMediaInteractionSurface(
                    kind: item.kind,
                    fileURL: url,
                    onDismiss: { dismiss() },
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
        } else {
            MemoryPhotoPage(
                url: url,
                onDismiss: { dismiss() },
                onEdit: onEdit,
                onDelete: onDelete
            )
        }
    }
}
