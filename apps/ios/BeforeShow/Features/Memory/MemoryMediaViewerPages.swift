import Photos
import SwiftUI
import UIKit

/// Video pages: a clear layer over the player for tap-to-close and long-press actions.
struct MemoryMediaInteractionSurface: View {
    let kind: MemoryMediaKind
    let fileURL: URL
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
            .modifier(MemoryMediaActions(
                isPresented: $isShowingActions,
                kind: kind,
                fileURL: fileURL,
                onDismiss: onDismiss,
                onEdit: onEdit,
                onDelete: onDelete
            ))
    }
}

/// Photo pages: the original image, zoomable; tap closes, long press manages.
struct MemoryPhotoPage: View {
    let url: URL
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isShowingActions = false

    var body: some View {
        BSZoomableImagePage(
            source: .file(url),
            onSingleTap: onDismiss,
            onLongPress: { isShowingActions = true }
        )
        .modifier(MemoryMediaActions(
            isPresented: $isShowingActions,
            kind: .photo,
            fileURL: url,
            onDismiss: onDismiss,
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }
}

/// Management sheet (save, edit, delete) and accessibility actions shared by photo
/// and video pages.
private struct MemoryMediaActions: ViewModifier {
    @Binding var isPresented: Bool
    let kind: MemoryMediaKind
    let fileURL: URL
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isSaving = false
    @State private var toast: BSToastPayload?

    func body(content: Content) -> some View {
        content
            .bsToastOverlay(toast, bottomPadding: 36)
            .sheet(isPresented: $isPresented) {
                MemoryMediaActionsSheet(
                    onEdit: {
                        isPresented = false
                        Task { @MainActor in
                            await Task.yield()
                            onEdit()
                        }
                    },
                    onDelete: {
                        isPresented = false
                        Task { @MainActor in
                            await Task.yield()
                            onDelete()
                        }
                    },
                    onSave: {
                        isPresented = false
                        Task { await save() }
                    }
                )
            }
            .accessibilityLabel(kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片"))
            .accessibilityHint(BSLocalization.text("轻点关闭，长按管理"))
            .accessibilityAction(named: BSLocalization.text("关闭"), onDismiss)
            .accessibilityAction(named: BSLocalization.text("编辑记忆"), onEdit)
            .accessibilityAction(named: BSLocalization.text("删除这条记忆"), onDelete)
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BSPhotoLibrarySaver.saveFile(fileURL, as: kind == .video ? .video : .photo)
            let message = kind == .video ? BSLocalization.text("已保存") : BSLocalization.text("已保存到相册")
            toast = BSToastPayload(tone: .success, message: message)
        } catch {
            // The library's own failure copy says "photo"; keep it only for the permission case.
            let message = if case FootprintPhotoSaveError.authorizationDenied = error {
                error.localizedDescription
            } else {
                BSLocalization.text("保存失败，请重试")
            }
            toast = BSToastPayload(tone: .failure, message: message)
        }
        let shown = toast
        try? await Task.sleep(for: .milliseconds(2200))
        if toast == shown { toast = nil }
    }
}
