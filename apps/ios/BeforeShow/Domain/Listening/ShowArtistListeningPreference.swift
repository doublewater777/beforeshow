import Foundation
import SwiftData

@Model
final class ShowArtistListeningPreference {
    @Attribute(.unique)
    private(set) var uniqueKey: String
    private(set) var showID: UUID
    private(set) var artistID: String
    var isExcluded: Bool
    var updatedAt: Date

    init(
        showID: UUID,
        artistID: String,
        isExcluded: Bool,
        updatedAt: Date = Date()
    ) {
        self.uniqueKey = Self.makeUniqueKey(showID: showID, artistID: artistID)
        self.showID = showID
        self.artistID = artistID
        self.isExcluded = isExcluded
        self.updatedAt = updatedAt
    }

    static func makeUniqueKey(showID: UUID, artistID: String) -> String {
        "\(showID.uuidString)|\(artistID)"
    }
}
