import Foundation
import SwiftData

enum ArtistWarmupConnectionState: String, Codable, Equatable {
    case notConnected
    case connected
}

@Model
final class ShowArtist {
    var id: UUID
    var showID: UUID
    var originalArtistLabel: String
    var originalOrder: Int
    var interestRawValue: String
    var appleMusicArtistID: String?
    var appleMusicArtistName: String?
    var appleMusicArtworkURL: String?
    private var connectionStateRawValue: String
    var confirmedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var interest: ArtistInterest {
        get { Self.interest(from: interestRawValue) }
        set {
            interestRawValue = Self.rawValue(for: newValue)
            updatedAt = Date()
        }
    }

    var connectionState: ArtistWarmupConnectionState {
        ArtistWarmupConnectionState(rawValue: connectionStateRawValue) ?? .notConnected
    }

    var isConnectedToAppleMusic: Bool {
        connectionState == .connected && appleMusicArtistID != nil
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        originalArtistLabel: String,
        originalOrder: Int,
        interest: ArtistInterest = .maybe,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.originalArtistLabel = originalArtistLabel
        self.originalOrder = originalOrder
        self.interestRawValue = Self.rawValue(for: interest)
        self.appleMusicArtistID = nil
        self.appleMusicArtistName = nil
        self.appleMusicArtworkURL = nil
        self.connectionStateRawValue = ArtistWarmupConnectionState.notConnected.rawValue
        self.confirmedAt = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func confirmAppleMusicArtist(
        id: String,
        name: String,
        artworkURL: String?,
        confirmedAt: Date = Date()
    ) {
        appleMusicArtistID = id
        appleMusicArtistName = name
        appleMusicArtworkURL = artworkURL
        connectionStateRawValue = ArtistWarmupConnectionState.connected.rawValue
        self.confirmedAt = confirmedAt
        updatedAt = confirmedAt
    }

    func clearAppleMusicConfirmation(updatedAt: Date = Date()) {
        appleMusicArtistID = nil
        appleMusicArtistName = nil
        appleMusicArtworkURL = nil
        connectionStateRawValue = ArtistWarmupConnectionState.notConnected.rawValue
        confirmedAt = nil
        self.updatedAt = updatedAt
    }

    private static func rawValue(for interest: ArtistInterest) -> String {
        switch interest {
        case .wanted:
            "wanted"
        case .maybe:
            "maybe"
        case .notInterested:
            "notInterested"
        }
    }

    private static func interest(from rawValue: String) -> ArtistInterest {
        switch rawValue {
        case "wanted":
            .wanted
        case "notInterested":
            .notInterested
        default:
            .maybe
        }
    }
}

enum ArtistCatalogSnapshotState: String, Codable, Equatable {
    case loading
    case complete
    case failed
}

@Model
final class ArtistCatalogSnapshot {
    @Attribute(.unique)
    var artistID: String
    var uniqueSongIDs: [String]
    private var stateRawValue: String
    var fetchedAt: Date?

    var state: ArtistCatalogSnapshotState {
        ArtistCatalogSnapshotState(rawValue: stateRawValue) ?? .loading
    }

    var denominatorSongCount: Int? {
        state == .complete ? uniqueSongIDs.count : nil
    }

    private init(
        artistID: String,
        songIDs: [String],
        state: ArtistCatalogSnapshotState,
        fetchedAt: Date?
    ) {
        self.artistID = artistID
        self.uniqueSongIDs = Self.uniqued(songIDs)
        self.stateRawValue = state.rawValue
        self.fetchedAt = fetchedAt
    }

    static func loading(artistID: String) -> ArtistCatalogSnapshot {
        ArtistCatalogSnapshot(artistID: artistID, songIDs: [], state: .loading, fetchedAt: nil)
    }

    static func failed(artistID: String, fetchedAt: Date) -> ArtistCatalogSnapshot {
        ArtistCatalogSnapshot(artistID: artistID, songIDs: [], state: .failed, fetchedAt: fetchedAt)
    }

    static func complete(
        artistID: String,
        songIDs: [String],
        fetchedAt: Date
    ) -> ArtistCatalogSnapshot {
        ArtistCatalogSnapshot(artistID: artistID, songIDs: songIDs, state: .complete, fetchedAt: fetchedAt)
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum CatalogSongCategory: String, Codable, Equatable {
    case album
    case single
    case collaboration
}

@Model
final class CatalogSong {
    @Attribute(.unique)
    var appleMusicSongID: String
    var title: String
    var albumTitle: String?
    var artworkURL: String?
    var duration: TimeInterval?
    var performingArtistIDs: [String]
    var performingArtistNames: [String]
    private var categoryRawValue: String

    var category: CatalogSongCategory {
        CatalogSongCategory(rawValue: categoryRawValue) ?? .album
    }

    init(
        appleMusicSongID: String,
        title: String,
        albumTitle: String? = nil,
        artworkURL: String? = nil,
        duration: TimeInterval? = nil,
        performingArtistIDs: [String],
        performingArtistNames: [String],
        category: CatalogSongCategory
    ) {
        self.appleMusicSongID = appleMusicSongID
        self.title = title
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.duration = duration
        self.performingArtistIDs = performingArtistIDs
        self.performingArtistNames = performingArtistNames
        self.categoryRawValue = category.rawValue
    }
}

enum SongFamiliaritySource: String, Codable, Equatable {
    case auto
    case manual
    case showRecall
}

@Model
final class SongFamiliarityRecord {
    @Attribute(.unique)
    var songID: String
    var heardAt: Date
    private var sourceRawValue: String

    var source: SongFamiliaritySource {
        SongFamiliaritySource(rawValue: sourceRawValue) ?? .manual
    }

    init(songID: String, heardAt: Date, source: SongFamiliaritySource) {
        self.songID = songID
        self.heardAt = heardAt
        self.sourceRawValue = source.rawValue
    }

    func update(heardAt: Date, source: SongFamiliaritySource) {
        self.heardAt = heardAt
        self.sourceRawValue = source.rawValue
    }
}

@Model
final class ShowSongImpression {
    var id: UUID
    var showID: UUID
    var songID: String
    @Attribute(.unique)
    var uniqueKey: String
    var wantsLive: Bool
    var hasFeeling: Bool
    var note: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        showID: UUID,
        songID: String,
        wantsLive: Bool,
        hasFeeling: Bool,
        note: String?,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.songID = songID
        self.uniqueKey = Self.makeUniqueKey(showID: showID, songID: songID)
        self.wantsLive = wantsLive
        self.hasFeeling = hasFeeling
        self.note = Self.normalized(note)
        self.updatedAt = updatedAt
    }

    static func makeUniqueKey(showID: UUID, songID: String) -> String {
        "\(showID.uuidString)|\(songID)"
    }

    func replace(wantsLive: Bool, hasFeeling: Bool, note: String?, updatedAt: Date = Date()) {
        self.wantsLive = wantsLive
        self.hasFeeling = hasFeeling
        self.note = Self.normalized(note)
        self.updatedAt = updatedAt
    }

    private static func normalized(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ShowArtistFamiliarityTier: String, Codable, Equatable {
    case firstListen
    case newListener
    case investedFan
    case familiarFan
    case deepFan
    case complete
}

@Model
final class ShowArtistFamiliaritySnapshot {
    @Attribute(.unique)
    private(set) var uniqueKey: String
    private(set) var showID: UUID
    private(set) var artistID: String
    private(set) var heardSongCount: Int
    private(set) var totalSongCount: Int
    private var tierRawValue: String
    private(set) var capturedAt: Date

    var tier: ShowArtistFamiliarityTier {
        ShowArtistFamiliarityTier(rawValue: tierRawValue) ?? .firstListen
    }

    private init(
        showID: UUID,
        artistID: String,
        heardSongCount: Int,
        totalSongCount: Int,
        tier: ShowArtistFamiliarityTier,
        capturedAt: Date
    ) {
        self.uniqueKey = Self.makeUniqueKey(showID: showID, artistID: artistID)
        self.showID = showID
        self.artistID = artistID
        self.heardSongCount = heardSongCount
        self.totalSongCount = totalSongCount
        self.tierRawValue = tier.rawValue
        self.capturedAt = capturedAt
    }

    static func capture(
        showID: UUID,
        artistID: String,
        heardSongCount: Int,
        totalSongCount: Int,
        tier: ShowArtistFamiliarityTier,
        capturedAt: Date = Date()
    ) -> ShowArtistFamiliaritySnapshot {
        ShowArtistFamiliaritySnapshot(
            showID: showID,
            artistID: artistID,
            heardSongCount: heardSongCount,
            totalSongCount: totalSongCount,
            tier: tier,
            capturedAt: capturedAt
        )
    }

    static func makeUniqueKey(showID: UUID, artistID: String) -> String {
        "\(showID.uuidString)|\(artistID)"
    }
}

@Model
final class ShowSetlistMemory {
    var id: UUID
    var showID: UUID
    var catalogSongID: String?
    var manualTitle: String?
    var manualArtistName: String?
    var heardAtShow: Date
    var isMostSurprising: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        showID: UUID,
        catalogSongID: String?,
        manualTitle: String?,
        manualArtistName: String?,
        heardAtShow: Date,
        isMostSurprising: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.catalogSongID = catalogSongID
        self.manualTitle = manualTitle
        self.manualArtistName = manualArtistName
        self.heardAtShow = heardAtShow
        self.isMostSurprising = isMostSurprising
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func update(
        heardAtShow: Date,
        isMostSurprising: Bool,
        updatedAt: Date = Date()
    ) {
        self.heardAtShow = heardAtShow
        self.isMostSurprising = isMostSurprising
        self.updatedAt = updatedAt
    }
}

@MainActor
struct ArtistWarmupRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func upsertImpression(
        showID: UUID,
        songID: String,
        wantsLive: Bool,
        hasFeeling: Bool,
        note: String?,
        updatedAt: Date = Date()
    ) throws -> ShowSongImpression {
        let uniqueKey = ShowSongImpression.makeUniqueKey(showID: showID, songID: songID)
        let descriptor = FetchDescriptor<ShowSongImpression>(
            predicate: #Predicate { $0.uniqueKey == uniqueKey }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.replace(
                wantsLive: wantsLive,
                hasFeeling: hasFeeling,
                note: note,
                updatedAt: updatedAt
            )
            return existing
        }

        let impression = ShowSongImpression(
            showID: showID,
            songID: songID,
            wantsLive: wantsLive,
            hasFeeling: hasFeeling,
            note: note,
            updatedAt: updatedAt
        )
        context.insert(impression)
        return impression
    }
}
