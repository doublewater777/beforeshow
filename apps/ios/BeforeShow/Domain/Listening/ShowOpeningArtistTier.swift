import Foundation
import SwiftData

@Model
final class ShowOpeningArtistTier {
    @Attribute(.unique)
    private(set) var uniqueKey: String
    private(set) var showID: UUID
    private(set) var artistID: String
    var artistNameAtCapture: String
    var tierRawValue: String
    var baselineCapturedAt: Date
    var catalogSnapshotFetchedAt: Date
    var catalogSongIDsAtResolution: [String] = []
    var resolvedAt: Date

    init(
        showID: UUID,
        artistID: String,
        artistNameAtCapture: String,
        tierRawValue: String,
        baselineCapturedAt: Date,
        catalogSnapshotFetchedAt: Date,
        catalogSongIDsAtResolution: [String] = [],
        resolvedAt: Date = Date()
    ) {
        self.uniqueKey = Self.makeUniqueKey(showID: showID, artistID: artistID)
        self.showID = showID
        self.artistID = artistID
        self.artistNameAtCapture = artistNameAtCapture
        self.tierRawValue = tierRawValue
        self.baselineCapturedAt = baselineCapturedAt
        self.catalogSnapshotFetchedAt = catalogSnapshotFetchedAt
        self.catalogSongIDsAtResolution = catalogSongIDsAtResolution
        self.resolvedAt = resolvedAt
    }

    static func makeUniqueKey(showID: UUID, artistID: String) -> String {
        "\(showID.uuidString)|\(artistID)"
    }
}
