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
    var currentTime: TimeInterval?
    var updatedAt: Date

    init(discData: Data, songID: String?, currentTime: TimeInterval = 0, updatedAt: Date = Date()) {
        self.discData = discData
        self.songID = songID
        self.currentTime = currentTime
        self.updatedAt = updatedAt
    }
}
