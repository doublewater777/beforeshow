import Foundation
import SwiftData

@Model
final class ShowWantsLiveSong {
    @Attribute(.unique)
    private(set) var uniqueKey: String
    private(set) var showID: UUID
    private(set) var songID: String
    var createdAt: Date

    init(showID: UUID, songID: String, createdAt: Date = Date()) {
        self.uniqueKey = Self.makeUniqueKey(showID: showID, songID: songID)
        self.showID = showID
        self.songID = songID
        self.createdAt = createdAt
    }

    static func makeUniqueKey(showID: UUID, songID: String) -> String {
        "\(showID.uuidString)|\(songID)"
    }
}
