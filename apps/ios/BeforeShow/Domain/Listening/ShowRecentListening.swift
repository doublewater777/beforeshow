import Foundation
import SwiftData

@Model
final class ShowRecentListening {
    var showID: UUID
    var discID: String
    var songID: String
    var playedAt: Date

    init(showID: UUID, discID: String, songID: String, playedAt: Date = Date()) {
        self.showID = showID
        self.discID = discID
        self.songID = songID
        self.playedAt = playedAt
    }
}

@Model
final class ListeningLoadedDiscState {
    var discData: Data
    var songID: String?
    var updatedAt: Date

    init(discData: Data, songID: String?, updatedAt: Date = Date()) {
        self.discData = discData
        self.songID = songID
        self.updatedAt = updatedAt
    }
}
