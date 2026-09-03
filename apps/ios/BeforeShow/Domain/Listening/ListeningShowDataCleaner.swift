import Foundation
import SwiftData

@MainActor
enum ListeningShowDataCleaner {
    static func deleteShowScopedData(showID: UUID, in modelContext: ModelContext) throws {
        for row in try modelContext.fetch(FetchDescriptor<ShowWantsLiveSong>()) where row.showID == showID {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowArtistListeningPreference>()) where row.showID == showID {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()) where row.showID == showID {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowOpeningArtistTier>()) where row.showID == showID {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowSetlistMemory>()) where row.showID == showID {
            modelContext.delete(row)
        }
    }

    /// Repairs any direct/bypassed Show deletion path (including development seeders)
    /// without touching global song familiarity or catalog cache.
    static func deleteOrphans(in modelContext: ModelContext) throws {
        let validShowIDs = Set(try modelContext.fetch(FetchDescriptor<Show>()).map(\.id))
        for row in try modelContext.fetch(FetchDescriptor<ShowWantsLiveSong>()) where !validShowIDs.contains(row.showID) {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowArtistListeningPreference>()) where !validShowIDs.contains(row.showID) {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()) where !validShowIDs.contains(row.showID) {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowOpeningArtistTier>()) where !validShowIDs.contains(row.showID) {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<ShowSetlistMemory>()) where !validShowIDs.contains(row.showID) {
            modelContext.delete(row)
        }
    }
}
