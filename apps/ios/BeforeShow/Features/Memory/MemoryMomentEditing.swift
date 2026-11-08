import Foundation
import SwiftData

/// Edits one moment without opening the old group editor.
@MainActor
enum MemoryMomentEditing {
    /// A text-only moment needs its line; a photo or video can drop it.
    static func setCaption(_ text: String, on moment: MemoryMoment, in context: ModelContext) throws {
        do {
            try moment.fragment.updateText(text)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Removes just this item; the memory itself goes when nothing else is left in it.
    static func delete(_ moment: MemoryMoment, in context: ModelContext) async throws {
        let fragment = moment.fragment
        if let item = moment.item, fragment.mediaItems.count > 1 {
            try await MemoryFragmentEditCoordinator.save(
                fragment,
                showID: fragment.showID,
                fullOrder: fragment.orderedMediaItems.map(\.id).filter { $0 != item.id },
                caption: fragment.text ?? "",
                removedIDs: [item.id],
                additions: [],
                draftID: UUID(),
                modelContext: context
            )
        } else {
            try await MemoryFragmentEditCoordinator.delete(fragment, showID: fragment.showID, modelContext: context)
        }
    }
}
