import Foundation

struct CompanionArtistSnapshot: Equatable, Sendable, Codable {
    var name: String
    var avatarURL: String?
    var appleMusicURL: String?
    var appleMusicArtistID: String?
    var albumArtworkURL: String?
}

/// Immutable show payload captured when the owner first creates a companion share.
/// New fields are encoded into one versioned Data field so the share remains a static
/// invitation snapshot rather than a live show-sync surface.
struct CompanionShowSnapshot: Equatable, Sendable, Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var showID: String
    /// Effective date kept for legacy matching / old clients.
    var showDate: Date
    var showName: String
    var showStartTime: Date
    /// Legacy combined `venue · city` value retained for backward compatibility.
    var showLocation: String?

    /// Original local `Show.date`. Nil for legacy invitations that only carried the
    /// effective date.
    var sourceShowDate: Date?
    var showEndDate: Date?
    var showEndTime: Date?
    var timeZoneSecondsFromGMT: Int?
    var endTimeZoneSecondsFromGMT: Int?
    var timeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var city: String?
    var venueName: String?
    var venueAddress: String?
    var artists: [CompanionArtistSnapshot]
    var coverImageURL: String?
    var showChangeStatusRawValue: String
    var postponedDate: Date?
    /// User-confirmed curtain time, frozen with the invitation. Optional keeps v1
    /// snapshots decodable without inventing a value.
    var endedAt: Date?
    /// Explicit lifecycle disposition for shows that were added directly to history.
    /// This must survive the snapshot even when the show is only one day old and would
    /// otherwise fall inside the ordinary post-show retention window on the recipient.
    var wasAddedAsHistorical: Bool?

    init(
        showID: String,
        showName: String,
        showDate: Date,
        showStartTime: Date,
        showLocation: String? = nil,
        schemaVersion: Int = CompanionShowSnapshot.currentSchemaVersion,
        sourceShowDate: Date? = nil,
        showEndDate: Date? = nil,
        showEndTime: Date? = nil,
        timeZoneSecondsFromGMT: Int? = nil,
        endTimeZoneSecondsFromGMT: Int? = nil,
        timeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        city: String? = nil,
        venueName: String? = nil,
        venueAddress: String? = nil,
        artists: [CompanionArtistSnapshot] = [],
        coverImageURL: String? = nil,
        showChangeStatusRawValue: String = ShowChangeStatus.scheduled.rawValue,
        postponedDate: Date? = nil,
        endedAt: Date? = nil,
        wasAddedAsHistorical: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.showID = showID
        self.showName = showName
        self.showDate = showDate
        self.showStartTime = showStartTime
        self.showLocation = showLocation
        self.sourceShowDate = sourceShowDate
        self.showEndDate = showEndDate
        self.showEndTime = showEndTime
        self.timeZoneSecondsFromGMT = timeZoneSecondsFromGMT
        self.endTimeZoneSecondsFromGMT = endTimeZoneSecondsFromGMT
        self.timeZoneIdentifier = timeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
        self.city = city
        self.venueName = venueName
        self.venueAddress = venueAddress
        self.artists = artists
        self.coverImageURL = coverImageURL
        self.showChangeStatusRawValue = showChangeStatusRawValue
        self.postponedDate = postponedDate
        self.endedAt = endedAt
        self.wasAddedAsHistorical = wasAddedAsHistorical
    }

    var changeStatus: ShowChangeStatus {
        ShowChangeStatus(rawValue: showChangeStatusRawValue) ?? .scheduled
    }
}
