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
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        showID: UUID,
        catalogSongID: String? = nil,
        manualTitle: String? = nil,
        manualArtistName: String? = nil,
        isMostSurprising: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.catalogSongID = catalogSongID
        self.manualTitle = manualTitle
        self.manualArtistName = manualArtistName
        self.isMostSurprising = isMostSurprising
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
