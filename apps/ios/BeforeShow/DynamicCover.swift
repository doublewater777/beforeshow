import Foundation
import SwiftData

enum DynamicCoverSource: String, Codable, CaseIterable, Sendable {
    case manual
    case generated
}

/// One optional, show-bound local video used as the dynamic side of a cover.
@Model
final class DynamicCover {
    static let maximumDuration: TimeInterval = 15
    static let maximumFileSize: Int64 = 100_000_000

    private(set) var id: UUID
    private(set) var showID: UUID
    @Attribute(.unique)
    private(set) var uniqueKey: String
    var relativePath: String
    var contentTypeIdentifier: String
    private var sourceRawValue: String?
    var videoDuration: TimeInterval
    var createdAt: Date
    var updatedAt: Date

    /// Cascade boundary with `Show`. `showID` remains a denormalized key for
    /// file paths and fetch predicates; the relationship keeps the model boundary
    /// enforceable when a show is deleted.
    var show: Show?

    init(
        id: UUID = UUID(),
        showID: UUID,
        relativePath: String,
        contentTypeIdentifier: String,
        source: DynamicCoverSource = .manual,
        videoDuration: TimeInterval,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.uniqueKey = Self.makeUniqueKey(showID: showID)
        self.relativePath = relativePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.sourceRawValue = source.rawValue
        self.videoDuration = videoDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var source: DynamicCoverSource {
        get { DynamicCoverSource(rawValue: sourceRawValue ?? "") ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }

    static func makeUniqueKey(showID: UUID) -> String {
        showID.uuidString
    }

    /// Dynamic-cover paths are limited to the show directory layout produced by
    /// `DynamicCoverMediaStore` so persisted records cannot escape the media root.
    static func isValidRelativePath(_ relativePath: String, showID: UUID) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        return components.count == 2
            && components[0] == showID.uuidString
            && !components[1].isEmpty
            && !components.contains(where: { $0 == "." || $0 == ".." })
    }

    func replaceVideo(
        relativePath: String,
        contentTypeIdentifier: String,
        videoDuration: TimeInterval
    ) {
        self.relativePath = relativePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.videoDuration = videoDuration
        updatedAt = Date()
    }
}
