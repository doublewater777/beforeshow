import Foundation
import SwiftData

@Model
final class ShowSetlistMemory {
    private(set) var id: UUID
    private(set) var showID: UUID
    var catalogSongID: String?
    var manualTitle: String?
    var manualArtistName: String?
    var isMostSurprising: Bool
    var wasPlayed: Bool?
    var order: Int?
    var createdAt: Date
    var updatedAt: Date

    var isPlayed: Bool { wasPlayed ?? true }

    init(
        id: UUID = UUID(),
        showID: UUID,
        catalogSongID: String? = nil,
        manualTitle: String? = nil,
        manualArtistName: String? = nil,
        isMostSurprising: Bool = false,
        wasPlayed: Bool? = nil,
        order: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.catalogSongID = catalogSongID
        self.manualTitle = manualTitle
        self.manualArtistName = manualArtistName
        self.isMostSurprising = isMostSurprising
        self.wasPlayed = wasPlayed
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
