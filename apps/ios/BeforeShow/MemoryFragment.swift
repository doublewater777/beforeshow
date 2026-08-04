import Foundation
import SwiftData

enum MemoryFragmentValidationError: Error, Equatable {
    case emptyContent
    case textTooLong
}

enum MemoryMediaKind: String, Codable, Equatable {
    case photo
    case video
}

@Model
final class MemoryFragment {
    var id: UUID
    var showID: UUID
    var text: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MemoryMediaItem.fragment)
    var mediaItems: [MemoryMediaItem] = []

    /// Model-level link to the owning `Show`. `showID` is retained as a denormalized
    /// key for file paths and fetch predicates, but this relationship is what makes
    /// the fragment<->show boundary enforceable: deleting a `Show` cascades to its
    /// fragments, and reconciliation can reject any fragment whose `showID` has no
    /// corresponding `Show`.
    var show: Show?

    init(
        id: UUID = UUID(),
        showID: UUID,
        text: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        self.id = id
        self.showID = showID
        self.text = try Self.normalized(text)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

    func appendMedia(_ item: MemoryMediaItem) {
        item.sortOrder = mediaItems.count
        mediaItems.append(item)
        updatedAt = Date()
    }

    func removeMedia(_ item: MemoryMediaItem) throws {
        if mediaItems.count == 1, mediaItems.first?.id == item.id, text == nil {
            throw MemoryFragmentValidationError.emptyContent
        }
        mediaItems.removeAll { $0.id == item.id }
        for (index, remaining) in orderedMediaItems.enumerated() {
            remaining.sortOrder = index
        }
        updatedAt = Date()
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
