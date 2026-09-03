import Foundation
import SwiftData

@Model
final class CatalogSong {
    @Attribute(.unique)
    private(set) var appleMusicSongID: String
    var title: String
    var artistName: String
    var albumID: String?
    var albumTitle: String?
    var artworkURL: String?
    var duration: TimeInterval?
    var performerArtistIDs: [String]
    var performerArtistNames: [String]
    var previewURL: String?
    var updatedAt: Date

    init(
        appleMusicSongID: String,
        title: String,
        artistName: String,
        albumID: String? = nil,
        albumTitle: String? = nil,
        artworkURL: String? = nil,
        duration: TimeInterval? = nil,
        performerArtistIDs: [String] = [],
        performerArtistNames: [String] = [],
        previewURL: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.appleMusicSongID = appleMusicSongID
        self.title = title
        self.artistName = artistName
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.duration = duration
        self.performerArtistIDs = performerArtistIDs
        self.performerArtistNames = performerArtistNames
        self.previewURL = previewURL
        self.updatedAt = updatedAt
    }

    func update(
        title: String,
        artistName: String,
        albumID: String?,
        albumTitle: String?,
        artworkURL: String?,
        duration: TimeInterval?,
        performerArtistIDs: [String],
        performerArtistNames: [String],
        previewURL: String?,
        updatedAt: Date
    ) {
        self.title = title
        self.artistName = artistName
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.duration = duration
        self.performerArtistIDs = performerArtistIDs
        self.performerArtistNames = performerArtistNames
        self.previewURL = previewURL
        self.updatedAt = updatedAt
    }
}
