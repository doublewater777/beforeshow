import Foundation
import SwiftUI

// MARK: - Presentation models

struct MemoryEditorLaunch: Identifiable, Hashable {
    enum Kind {
        case createText
        case createMedia(draftID: UUID, media: [MemoryDraftMedia])
        case edit(MemoryFragment)
    }

    let id = UUID()
    let kind: Kind

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MemoryViewerTarget: Identifiable, Hashable {
    let id = UUID()
    let fragment: MemoryFragment
    let initialIndex: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MemoryInternalPushes: ViewModifier {
    @Binding var editorLaunch: MemoryEditorLaunch?
    @Binding var viewerTarget: MemoryViewerTarget?
    let onCreate: @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void
    let onEdit: @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void
    let onViewerEdit: (MemoryFragment) -> Void
    let onViewerDelete: (MemoryFragment) -> Void
    let onViewerDismissed: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $editorLaunch) { launch in
                MemoryUnifiedEditorView(
                    launch: launch,
                    onSaveCreate: onCreate,
                    onSaveEdit: onEdit
                )
            }
            .fullScreenCover(item: $viewerTarget, onDismiss: onViewerDismissed) { target in
                MemoryMediaViewer(
                    fragment: target.fragment,
                    initialIndex: target.initialIndex,
                    onEdit: { onViewerEdit(target.fragment) },
                    onDelete: { onViewerDelete(target.fragment) }
                )
            }
    }
}

extension View {
    func memoryInternalPushes(
        editorLaunch: Binding<MemoryEditorLaunch?>,
        viewerTarget: Binding<MemoryViewerTarget?>,
        onCreate: @escaping @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void,
        onEdit: @escaping @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void,
        onViewerEdit: @escaping (MemoryFragment) -> Void,
        onViewerDelete: @escaping (MemoryFragment) -> Void,
        onViewerDismissed: @escaping () -> Void
    ) -> some View {
        modifier(
            MemoryInternalPushes(
                editorLaunch: editorLaunch,
                viewerTarget: viewerTarget,
                onCreate: onCreate,
                onEdit: onEdit,
                onViewerEdit: onViewerEdit,
                onViewerDelete: onViewerDelete,
                onViewerDismissed: onViewerDismissed
            )
        )
    }
}

enum MemoryPendingPresentation {
    case edit(MemoryFragment)
    case delete(MemoryFragment)
}

enum MemoryCreateDestination {
    case text
    case library
    case camera
}

struct MemoryEditorItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case existing(
            id: UUID,
            relativePath: String,
            thumbnailRelativePath: String?,
            mediaKind: MemoryMediaKind,
            videoDuration: TimeInterval?
        )
        case draft(MemoryDraftMedia)
    }

    let id: UUID
    var kind: Kind

    var previewRelativePath: String {
        switch kind {
        case .existing(_, let relativePath, let thumbnailRelativePath, _, _):
            return thumbnailRelativePath ?? relativePath
        case .draft(let draft):
            return draft.thumbnailStagedRelativePath ?? draft.stagedRelativePath
        }
    }

    var mediaKind: MemoryMediaKind {
        switch kind {
        case .existing(_, _, _, let mediaKind, _):
            return mediaKind
        case .draft(let draft):
            return draft.kind
        }
    }

    var isDraft: Bool {
        if case .draft = kind { return true }
        return false
    }

    var draftMedia: MemoryDraftMedia? {
        if case .draft(let draft) = kind { return draft }
        return nil
    }

    var existingID: UUID? {
        if case .existing(let id, _, _, _, _) = kind { return id }
        return nil
    }
}
