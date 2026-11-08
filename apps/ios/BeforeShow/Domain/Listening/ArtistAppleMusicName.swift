import Foundation
import SwiftData

extension ArtistSlot {
    /// Links the slot to its Apple Music artist and takes that artist's name.
    mutating func adoptAppleMusicIdentity(_ artist: RecognizedArtist) {
        appleMusicArtistID = artist.id
        appleMusicURL = artist.appleMusicURL?.absoluteString
        let appleMusicName = artist.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appleMusicName.isEmpty { name = appleMusicName }
    }
}

/// 匹配到 Apple Music 的艺人一律用 Apple Music 的名字，现场阵容与时刻表一致。
enum ArtistAppleMusicName {
    /// Slots renamed to their Apple Music names, or nil when nothing changes.
    static func adopting(_ namesByID: [String: String], in slots: [ArtistSlot]) -> [ArtistSlot]? {
        var renamed = slots
        var changed = false
        for index in renamed.indices {
            guard let id = AppleMusicArtistIdentity.artistID(for: renamed[index]),
                  let name = namesByID[id], renamed[index].name != name else { continue }
            renamed[index].name = name
            changed = true
        }
        return changed ? renamed : nil
    }

    /// Renames every matched artist whose Apple Music name is cached locally.
    @MainActor @discardableResult
    static func sync(in context: ModelContext) throws -> Bool {
        var namesByID: [String: String] = [:]
        for snapshot in try context.fetch(FetchDescriptor<ArtistCatalogSnapshot>()) {
            let name = snapshot.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { namesByID[snapshot.artistID] = name }
        }
        guard !namesByID.isEmpty else { return false }
        var changed = false
        for show in try context.fetch(FetchDescriptor<Show>()) {
            guard let renamed = adopting(namesByID, in: show.artists) else { continue }
            show.artists = renamed
            show.updatedAt = Date()
            changed = true
        }
        for performance in try context.fetch(FetchDescriptor<TimetablePerformance>()) {
            guard let id = performance.appleMusicArtistID, let name = namesByID[id],
                  performance.artistName != name else { continue }
            performance.artistName = name
            changed = true
        }
        if changed { try context.save() }
        return changed
    }
}
