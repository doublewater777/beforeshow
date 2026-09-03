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
}
