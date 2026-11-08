import Foundation
import SwiftData

enum DynamicCoverSource: String, Codable, CaseIterable, Sendable {
    case manual
    case generated
}

/// Deprecated: the retired dynamic-cover video. Kept only so shipped
/// stores stay readable; `DynamicCoverRetirement` deletes old rows once at launch.
/// Removing the model or any field needs its own migration plan.
@Model
final class DynamicCover {
    private(set) var id: UUID
    private(set) var showID: UUID
    @Attribute(.unique)
    private(set) var uniqueKey: String
    var relativePath: String
    /// First-frame poster generated at import time; lets synchronous cover
    /// resolvers use the dynamic cover without decoding the video.
    var posterRelativePath: String?
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
        posterRelativePath: String? = nil,
        contentTypeIdentifier: String,
        source: DynamicCoverSource = .manual,
        videoDuration: TimeInterval,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.uniqueKey = showID.uuidString
        self.relativePath = relativePath
        self.posterRelativePath = posterRelativePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.sourceRawValue = source.rawValue
        self.videoDuration = videoDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
