import Foundation
import SwiftData

@MainActor
struct ArtistWarmupSnapshotService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func captureOpeningSnapshots(
        for show: Show,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [ShowArtistFamiliaritySnapshot] {
        guard isOpeningSnapshotEligible(show: show, now: now, calendar: calendar) else {
            return []
        }

        let showID = show.id
        let artists = try context.fetch(
            FetchDescriptor<ShowArtist>(
                predicate: #Predicate { $0.showID == showID }
            )
        )

        var snapshots: [ShowArtistFamiliaritySnapshot] = []
        for artist in artists where artist.isConnectedToAppleMusic {
            guard let artistID = artist.appleMusicArtistID else { continue }
            if let existing = try familiaritySnapshot(showID: showID, artistID: artistID) {
                snapshots.append(existing)
                continue
            }

            guard let summary = try familiaritySummary(artistID: artistID) else {
                continue
            }

            let snapshot = ShowArtistFamiliaritySnapshot.capture(
                showID: showID,
                artistID: artistID,
                heardSongCount: summary.heardSongCount,
                totalSongCount: summary.catalogSongCount,
                tier: Self.snapshotTier(forPercent: summary.percent),
                capturedAt: now
            )
            context.insert(snapshot)
            snapshots.append(snapshot)
        }

        return snapshots
    }

    @discardableResult
    func confirmCatalogSongHeardAtShow(
        showID: UUID,
        songID: String,
        heardAtShow: Date,
        isMostSurprising: Bool = false,
        now: Date = Date()
    ) throws -> ShowSetlistMemory {
        let memory: ShowSetlistMemory
        if let existing = try setlistMemory(showID: showID, songID: songID) {
            memory = existing
        } else {
            memory = ShowSetlistMemory(
                showID: showID,
                catalogSongID: songID,
                manualTitle: nil,
                manualArtistName: nil,
                heardAtShow: heardAtShow,
                isMostSurprising: false,
                createdAt: now,
                updatedAt: now
            )
            context.insert(memory)
        }

        if isMostSurprising {
            try clearMostSurprisingMemories(showID: showID, except: memory.id, updatedAt: now)
        }
        memory.update(
            heardAtShow: heardAtShow,
            isMostSurprising: isMostSurprising,
            updatedAt: now
        )

        try upsertFamiliarity(songID: songID, heardAt: heardAtShow)
        return memory
    }

    @discardableResult
    func rememberManualSongAtShow(
        showID: UUID,
        title: String,
        artistName: String?,
        heardAtShow: Date,
        isMostSurprising: Bool = false,
        now: Date = Date()
    ) throws -> ShowSetlistMemory {
        let memory = ShowSetlistMemory(
            showID: showID,
            catalogSongID: nil,
            manualTitle: Self.normalized(title),
            manualArtistName: Self.normalized(artistName),
            heardAtShow: heardAtShow,
            isMostSurprising: false,
            createdAt: now,
            updatedAt: now
        )
        context.insert(memory)

        if isMostSurprising {
            try clearMostSurprisingMemories(showID: showID, except: memory.id, updatedAt: now)
        }
        memory.update(
            heardAtShow: heardAtShow,
            isMostSurprising: isMostSurprising,
            updatedAt: now
        )

        return memory
    }

    func deleteShowLocalWarmupRecords(for showID: UUID) throws {
        try deleteRecords(FetchDescriptor<ShowArtist>(predicate: #Predicate { $0.showID == showID }))
        try deleteRecords(FetchDescriptor<ShowSongImpression>(predicate: #Predicate { $0.showID == showID }))
        try deleteRecords(FetchDescriptor<ShowArtistFamiliaritySnapshot>(predicate: #Predicate { $0.showID == showID }))
        try deleteRecords(FetchDescriptor<ShowSetlistMemory>(predicate: #Predicate { $0.showID == showID }))
    }

    private func isOpeningSnapshotEligible(
        show: Show,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch show.changeStatus {
        case .canceled:
            return false
        case .postponed where show.postponedDate == nil:
            return false
        case .scheduled, .postponed:
            let eventCalendar = show.timingCalendar(fallback: calendar)
            let startDay = eventCalendar.startOfDay(for: show.effectiveDate)
            let startComponents = eventCalendar.dateComponents([.hour, .minute, .second], from: show.startTime)
            guard let opening = eventCalendar.date(
                bySettingHour: startComponents.hour ?? 0,
                minute: startComponents.minute ?? 0,
                second: startComponents.second ?? 0,
                of: startDay
            ) else {
                return false
            }
            return opening <= now
        }
    }

    private func familiaritySnapshot(
        showID: UUID,
        artistID: String
    ) throws -> ShowArtistFamiliaritySnapshot? {
        let uniqueKey = ShowArtistFamiliaritySnapshot.makeUniqueKey(showID: showID, artistID: artistID)
        return try context.fetch(
            FetchDescriptor<ShowArtistFamiliaritySnapshot>(
                predicate: #Predicate { $0.uniqueKey == uniqueKey }
            )
        ).first
    }

    private func familiaritySummary(artistID: String) throws -> ArtistFamiliaritySummary? {
        guard let catalog = try context.fetch(
            FetchDescriptor<ArtistCatalogSnapshot>(
                predicate: #Predicate { $0.artistID == artistID }
            )
        ).first,
              catalog.state == .complete,
              !catalog.uniqueSongIDs.isEmpty else {
            return nil
        }

        let familiarSongIDs = try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).map(\.songID)
        return ArtistFamiliarity.summary(
            catalogEnumeration: .complete(songIDs: catalog.uniqueSongIDs),
            heardSongIDs: familiarSongIDs
        )
    }

    private func setlistMemory(
        showID: UUID,
        songID: String
    ) throws -> ShowSetlistMemory? {
        let showMemories = try context.fetch(
            FetchDescriptor<ShowSetlistMemory>(
                predicate: #Predicate { $0.showID == showID }
            )
        )
        return showMemories.first { $0.catalogSongID == songID }
    }

    private func upsertFamiliarity(songID: String, heardAt: Date) throws {
        let descriptor = FetchDescriptor<SongFamiliarityRecord>(
            predicate: #Predicate { $0.songID == songID }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.update(heardAt: heardAt, source: .showRecall)
            return
        }

        context.insert(SongFamiliarityRecord(songID: songID, heardAt: heardAt, source: .showRecall))
    }

    private func clearMostSurprisingMemories(
        showID: UUID,
        except memoryID: UUID,
        updatedAt: Date
    ) throws {
        let memories = try context.fetch(
            FetchDescriptor<ShowSetlistMemory>(
                predicate: #Predicate { $0.showID == showID && $0.isMostSurprising }
            )
        )
        for memory in memories where memory.id != memoryID {
            memory.update(
                heardAtShow: memory.heardAtShow,
                isMostSurprising: false,
                updatedAt: updatedAt
            )
        }
    }

    private func deleteRecords<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws {
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
    }

    private static func snapshotTier(forPercent percent: Int) -> ShowArtistFamiliarityTier {
        switch percent {
        case 0:
            .firstListen
        case 1...24:
            .newListener
        case 25...49:
            .investedFan
        case 50...74:
            .familiarFan
        case 75...99:
            .deepFan
        default:
            .complete
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
