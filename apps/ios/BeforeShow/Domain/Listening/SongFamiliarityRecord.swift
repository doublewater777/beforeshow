import Foundation
import SwiftData

@Model
final class SongFamiliarityRecord {
    @Attribute(.unique)
    private(set) var songID: String
    var manualConfirmedAt: Date?
    var actualListeningAt: Date?
    var updatedAt: Date

    init(
        songID: String,
        manualConfirmedAt: Date? = nil,
        actualListeningAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.songID = songID
        self.manualConfirmedAt = manualConfirmedAt
        self.actualListeningAt = actualListeningAt
        self.updatedAt = updatedAt
    }

    func confirmManual(at date: Date) {
        manualConfirmedAt = manualConfirmedAt ?? date
        updatedAt = date
    }

    func clearManual(at date: Date) {
        manualConfirmedAt = nil
        updatedAt = date
    }

    func confirmActualListening(at date: Date) {
        actualListeningAt = actualListeningAt ?? date
        updatedAt = date
    }
}
