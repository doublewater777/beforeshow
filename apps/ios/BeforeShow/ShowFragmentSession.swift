import Foundation
import SwiftData

/// Deep module for 现场碎片 compose/delete transactions.
///
/// Deletion test: removing this module pushes canSave rules, gallery+audio
/// attach orchestration, and delete-via-LocalAppDataDeletionService back into
/// ShowFragmentListView. Media picking / recording stay as UI adapters.
@MainActor
struct ShowFragmentSession {
    let show: Show
    private let deletionService: LocalAppDataDeletionService

    init(
        show: Show,
        deletionService: LocalAppDataDeletionService = LocalAppDataDeletionService(
            audioStorage: .applicationSupport()
        )
    ) {
        self.show = show
        self.deletionService = deletionService
    }

    func canSave(
        text: String,
        galleryReferenceCount: Int,
        hasAudio: Bool
    ) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || galleryReferenceCount > 0
            || hasAudio
    }

    /// Create and persist a fragment with optional gallery + audio attachments.
    @discardableResult
    func create(
        text: String?,
        galleryReferences: [(localIdentifier: String, kind: ShowFragmentGalleryMediaKind)],
        audioRelativePath: String?,
        audioDuration: TimeInterval?,
        in context: ModelContext
    ) throws -> ShowFragment {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = (trimmed?.isEmpty == false) ? trimmed : nil
        let fragment = try ShowFragment(show: show, text: normalizedText)

        for reference in galleryReferences {
            _ = fragment.addGalleryMediaReference(
                assetLocalIdentifier: reference.localIdentifier,
                kind: reference.kind
            )
        }

        if let audioRelativePath {
            _ = fragment.attachAudioReference(
                relativePath: audioRelativePath,
                duration: audioDuration
            )
        }

        context.insert(fragment)
        try context.save()
        return fragment
    }

    func delete(_ fragment: ShowFragment, in context: ModelContext) throws {
        try deletionService.deleteFragment(fragment, in: context)
        try context.save()
    }
}
