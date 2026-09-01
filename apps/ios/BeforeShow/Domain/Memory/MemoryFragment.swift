import Foundation
import SwiftData

enum MemoryFragmentValidationError: Error, Equatable {
    case emptyContent
    case textTooLong
    case mediaLimitExceeded
}

enum MemoryMediaKind: String, Codable, Equatable {
    case photo
    case video
}

@Model
final class MemoryFragment {
    static let maximumMediaCount = 10

    var id: UUID
    var showID: UUID
    var text: String?
    var createdAt: Date
    var updatedAt: Date
    /// Creation-time phase snapshot retained for legacy data and migrations.
    /// The memory timeline resolves the visible phase from the current Show timing.
    var phaseRawValue: String?

    @Relationship(deleteRule: .cascade, inverse: \MemoryMediaItem.fragment)
    var mediaItems: [MemoryMediaItem] = []

    /// Model-level link to the owning `Show`. `showID` is retained as a denormalized
    /// key for file paths and fetch predicates, but this relationship is what makes
    /// the fragment<->show boundary enforceable: deleting a `Show` cascades to its
    /// fragments, and reconciliation can reject any fragment whose `showID` has no
    /// corresponding `Show`.
    var show: Show?

    var phase: MemoryFragmentPhase {
        get { phaseRawValue.flatMap(MemoryFragmentPhase.init(rawValue:)) ?? .live }
        set { phaseRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        text: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        phase: MemoryFragmentPhase = .live
    ) throws {
        self.id = id
        self.showID = showID
        self.text = try Self.normalized(text)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phaseRawValue = phase.rawValue
    }

    var orderedMediaItems: [MemoryMediaItem] {
        mediaItems.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    func updateText(_ text: String?) throws {
        let normalized = try Self.normalized(text)
        guard normalized != nil || !mediaItems.isEmpty else {
            throw MemoryFragmentValidationError.emptyContent
        }
        self.text = normalized
        updatedAt = Date()
    }

    func appendMedia(_ item: MemoryMediaItem) throws {
        guard mediaItems.count < Self.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }
        item.sortOrder = mediaItems.count
        mediaItems.append(item)
        updatedAt = Date()
    }

    func removeMedia(_ item: MemoryMediaItem) throws {
        if mediaItems.count == 1, mediaItems.first?.id == item.id, text == nil {
            throw MemoryFragmentValidationError.emptyContent
        }
        mediaItems.removeAll { $0.id == item.id }
        renumberMediaOrder()
        updatedAt = Date()
    }

    /// Reorder media to match `orderedIDs`. Unknown IDs are ignored; missing current
    /// items keep relative order at the end.
    func reorderMedia(orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: mediaItems.map { ($0.id, $0) })
        var next = 0
        var seen = Set<UUID>()
        for id in orderedIDs {
            guard let item = byID[id], !seen.contains(id) else { continue }
            item.sortOrder = next
            next += 1
            seen.insert(id)
        }
        for item in orderedMediaItems where !seen.contains(item.id) {
            item.sortOrder = next
            next += 1
        }
        updatedAt = Date()
    }

    /// Apply a full media edit as one final-state transaction.
    /// Validates only the final set, so intermediate empty/limit states from
    /// replace-at-capacity or textless single-media swaps do not fail mid-edit.
    func applyMediaEdit(
        removingIDs: Set<UUID>,
        adding: [MemoryMediaItem],
        finalOrder: [UUID]
    ) throws {
        let remaining = orderedMediaItems.filter { !removingIDs.contains($0.id) }
        let finalCount = remaining.count + adding.count
        guard finalCount <= Self.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }
        guard text != nil || finalCount > 0 else {
            throw MemoryFragmentValidationError.emptyContent
        }

        if !removingIDs.isEmpty {
            mediaItems.removeAll { removingIDs.contains($0.id) }
        }
        for item in adding {
            mediaItems.append(item)
        }

        // Prefer caller final order; fall back to remaining + additions order.
        let desired = finalOrder.isEmpty
            ? remaining.map(\.id) + adding.map(\.id)
            : finalOrder
        reorderMedia(orderedIDs: desired)
        updatedAt = Date()
    }

    /// Hard-cap helper for migration / defensive saves. Keeps the first 10 ordered items.
    /// Returns media that must be deleted from disk by the caller.
    @discardableResult
    func trimMediaToMaximum() -> [MemoryMediaItem] {
        let ordered = orderedMediaItems
        guard ordered.count > Self.maximumMediaCount else { return [] }
        let overflow = Array(ordered.dropFirst(Self.maximumMediaCount))
        for item in overflow {
            mediaItems.removeAll { $0.id == item.id }
        }
        renumberMediaOrder()
        updatedAt = Date()
        return overflow
    }

    private func renumberMediaOrder() {
        for (index, remaining) in orderedMediaItems.enumerated() {
            remaining.sortOrder = index
        }
    }

    static func normalized(_ text: String?) throws -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= 500 else {
            throw MemoryFragmentValidationError.textTooLong
        }
        return normalized
    }
}

@Model
final class MemoryMediaItem {
    var id: UUID
    private var kindRawValue: String
    var relativePath: String
    var thumbnailRelativePath: String?
    var contentTypeIdentifier: String
    var videoDuration: TimeInterval?
    var sortOrder: Int
    var createdAt: Date
    var fragment: MemoryFragment?

    var kind: MemoryMediaKind {
        get { MemoryMediaKind(rawValue: kindRawValue) ?? .photo }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID,
        kind: MemoryMediaKind,
        relativePath: String,
        thumbnailRelativePath: String?,
        contentTypeIdentifier: String,
        videoDuration: TimeInterval?,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.relativePath = relativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.videoDuration = videoDuration
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
