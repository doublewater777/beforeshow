import Foundation
import SwiftData

@Model
final class ArtistCatalogSnapshot {
    @Attribute(.unique)
    private(set) var artistID: String
    var artistName: String
    var artworkURL: String?
    var editorialText: String?
    var genreNames: [String]
    var orderedSongIDs: [String]
    var topSongIDs: [String]
    var albumIDs: [String]
    var fetchedAt: Date

    init(
        artistID: String,
        artistName: String,
        artworkURL: String? = nil,
        editorialText: String? = nil,
        genreNames: [String] = [],
        orderedSongIDs: [String] = [],
        topSongIDs: [String] = [],
        albumIDs: [String] = [],
        fetchedAt: Date = Date()
    ) {
        self.artistID = artistID
        self.artistName = artistName
        self.artworkURL = artworkURL
        self.editorialText = editorialText
        self.genreNames = genreNames
        self.orderedSongIDs = orderedSongIDs
        self.topSongIDs = topSongIDs
        self.albumIDs = albumIDs
        self.fetchedAt = fetchedAt
    }

    func update(
        artistName: String,
        artworkURL: String?,
        editorialText: String?,
        genreNames: [String],
        orderedSongIDs: [String],
        topSongIDs: [String],
        albumIDs: [String],
        fetchedAt: Date
    ) {
        self.artistName = artistName
        self.artworkURL = artworkURL
        self.editorialText = editorialText
        self.genreNames = genreNames
        self.orderedSongIDs = orderedSongIDs
        self.topSongIDs = topSongIDs
        self.albumIDs = albumIDs
        self.fetchedAt = fetchedAt
    }
}
