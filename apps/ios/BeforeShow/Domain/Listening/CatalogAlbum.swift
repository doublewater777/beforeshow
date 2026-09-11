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
    private var storedArtistNames: [String]?
    var editorialText: String?
    private var storedGenreNames: [String]?
    var copyright: String?
    var recordLabelName: String?
    var contentRatingRawValue: String?
    private var storedAudioVariantRawValues: [String]?
    var isAppleDigitalMaster: Bool?
    var isCompilation: Bool?
    var isSingle: Bool?
    var appleMusicURL: String?
    var orderedTrackIDs: [String]
    var updatedAt: Date

    var artistNames: [String] { storedArtistNames ?? [] }
    var genreNames: [String] { storedGenreNames ?? [] }
    var audioVariantRawValues: [String] { storedAudioVariantRawValues ?? [] }

    init(
        appleMusicAlbumID: String,
        title: String,
        artworkURL: String? = nil,
        releaseDate: Date? = nil,
        artistIDs: [String] = [],
        artistNames: [String] = [],
        editorialText: String? = nil,
        genreNames: [String] = [],
        copyright: String? = nil,
        recordLabelName: String? = nil,
        contentRatingRawValue: String? = nil,
        audioVariantRawValues: [String] = [],
        isAppleDigitalMaster: Bool? = nil,
        isCompilation: Bool? = nil,
        isSingle: Bool? = nil,
        appleMusicURL: String? = nil,
        orderedTrackIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.appleMusicAlbumID = appleMusicAlbumID
        self.title = title
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.artistIDs = artistIDs
        self.storedArtistNames = artistNames
        self.editorialText = editorialText
        self.storedGenreNames = genreNames
        self.copyright = copyright
        self.recordLabelName = recordLabelName
        self.contentRatingRawValue = contentRatingRawValue
        self.storedAudioVariantRawValues = audioVariantRawValues
        self.isAppleDigitalMaster = isAppleDigitalMaster
        self.isCompilation = isCompilation
        self.isSingle = isSingle
        self.appleMusicURL = appleMusicURL
        self.orderedTrackIDs = orderedTrackIDs
        self.updatedAt = updatedAt
    }

    func update(
        title: String,
        artworkURL: String?,
        releaseDate: Date?,
        artistIDs: [String],
        artistNames: [String],
        editorialText: String?,
        genreNames: [String],
        copyright: String?,
        recordLabelName: String?,
        contentRatingRawValue: String?,
        audioVariantRawValues: [String],
        isAppleDigitalMaster: Bool?,
        isCompilation: Bool?,
        isSingle: Bool?,
        appleMusicURL: String?,
        orderedTrackIDs: [String],
        updatedAt: Date
    ) {
        self.title = title
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.artistIDs = artistIDs
        self.storedArtistNames = artistNames
        self.editorialText = editorialText
        self.storedGenreNames = genreNames
        self.copyright = copyright
        self.recordLabelName = recordLabelName
        self.contentRatingRawValue = contentRatingRawValue
        self.storedAudioVariantRawValues = audioVariantRawValues
        self.isAppleDigitalMaster = isAppleDigitalMaster
        self.isCompilation = isCompilation
        self.isSingle = isSingle
        self.appleMusicURL = appleMusicURL
        self.orderedTrackIDs = orderedTrackIDs
        self.updatedAt = updatedAt
    }
}
