import Foundation
import SwiftData

@Model
final class CatalogAlbum {
    @Attribute(.unique)
    private(set) var appleMusicAlbumID: String
    var title: String
    var artworkURL: String?
    var releaseDate: Date?
    var artistIDs: [String]
    var orderedTrackIDs: [String]
    var updatedAt: Date

    init(
        appleMusicAlbumID: String,
        title: String,
        artworkURL: String? = nil,
        releaseDate: Date? = nil,
        artistIDs: [String] = [],
        orderedTrackIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.appleMusicAlbumID = appleMusicAlbumID
        self.title = title
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.artistIDs = artistIDs
        self.orderedTrackIDs = orderedTrackIDs
        self.updatedAt = updatedAt
    }

    func update(
        title: String,
        artworkURL: String?,
        releaseDate: Date?,
        artistIDs: [String],
        orderedTrackIDs: [String],
        updatedAt: Date
    ) {
        self.title = title
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.artistIDs = artistIDs
        self.orderedTrackIDs = orderedTrackIDs
        self.updatedAt = updatedAt
    }
}
