import Foundation
import SwiftData

enum ShowFragmentValidationError: Error, Equatable {
    case emptyText
    case sameShowMove
}

enum ShowFragmentGalleryMediaKind: String, CaseIterable, Codable, Equatable {
    case photo
    case video
}

@Model
final class ShowFragment {
    var id: UUID
    var text: String?
    var createdAt: Date
    var updatedAt: Date

    var show: Show

    @Relationship(deleteRule: .cascade, inverse: \ShowFragmentGalleryMediaReference.fragment)
    var galleryMediaReferences: [ShowFragmentGalleryMediaReference] = []

    @Relationship(deleteRule: .cascade, inverse: \ShowFragmentAudioReference.fragment)
    var audioReference: ShowFragmentAudioReference?

    init(
        id: UUID = UUID(),
        show: Show,
        text: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        self.id = id
        self.show = show
        self.text = try Self.normalizedText(text)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updateText(_ text: String?) throws {
        self.text = try Self.normalizedText(text)
        touch()
    }

    func addGalleryMediaReference(
        assetLocalIdentifier: String,
        kind: ShowFragmentGalleryMediaKind,
        createdAt: Date = Date()
    ) -> ShowFragmentGalleryMediaReference {
        let reference = ShowFragmentGalleryMediaReference(
            fragment: self,
            assetLocalIdentifier: assetLocalIdentifier,
            kind: kind,
            createdAt: createdAt
        )
        galleryMediaReferences.append(reference)
        touch()
        return reference
    }

    func attachAudioReference(
        relativePath: String,
        duration: TimeInterval? = nil,
        createdAt: Date = Date()
    ) -> ShowFragmentAudioReference {
        let reference = ShowFragmentAudioReference(
            fragment: self,
            relativePath: relativePath,
            duration: duration,
            createdAt: createdAt
        )
        audioReference = reference
        touch()
        return reference
    }

    func move(to destinationShow: Show) throws {
        guard destinationShow.id != show.id else {
            throw ShowFragmentValidationError.sameShowMove
        }

        show = destinationShow
        touch()
    }

    static func sortedByCreationTime(_ fragments: [ShowFragment]) -> [ShowFragment] {
        fragments.sorted { first, second in
            if first.createdAt == second.createdAt {
                return first.id.uuidString < second.id.uuidString
            }

            return first.createdAt < second.createdAt
        }
    }

    private static func normalizedText(_ text: String?) throws -> String? {
        guard let text else { return nil }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ShowFragmentValidationError.emptyText
        }

        return trimmedText
    }

    private func touch() {
        updatedAt = Date()
    }
}

@Model
final class ShowFragmentGalleryMediaReference {
    var id: UUID
    var assetLocalIdentifier: String
    var createdAt: Date
    var lastKnownMissingAt: Date?

    private var kindRawValue: String

    var fragment: ShowFragment?

    var kind: ShowFragmentGalleryMediaKind {
        get { ShowFragmentGalleryMediaKind(rawValue: kindRawValue) ?? .photo }
        set { kindRawValue = newValue.rawValue }
    }

    var isMissing: Bool {
        lastKnownMissingAt != nil
    }

    init(
        id: UUID = UUID(),
        fragment: ShowFragment,
        assetLocalIdentifier: String,
        kind: ShowFragmentGalleryMediaKind,
        createdAt: Date = Date(),
        lastKnownMissingAt: Date? = nil
    ) {
        self.id = id
        self.fragment = fragment
        self.assetLocalIdentifier = assetLocalIdentifier
        self.kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.lastKnownMissingAt = lastKnownMissingAt
    }

    func markMissing(at date: Date = Date()) {
        lastKnownMissingAt = date
    }

    func markAvailable() {
        lastKnownMissingAt = nil
    }
}

@Model
final class ShowFragmentAudioReference {
    var id: UUID
    var relativePath: String
    var duration: TimeInterval?
    var createdAt: Date

    var fragment: ShowFragment?

    init(
        id: UUID = UUID(),
        fragment: ShowFragment,
        relativePath: String,
        duration: TimeInterval? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fragment = fragment
        self.relativePath = relativePath
        self.duration = duration
        self.createdAt = createdAt
    }
}
