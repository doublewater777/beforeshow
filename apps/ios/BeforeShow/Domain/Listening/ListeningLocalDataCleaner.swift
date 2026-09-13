import SwiftData

@MainActor
enum ListeningLocalDataCleaner {
    static func deleteAll(in modelContext: ModelContext) throws {
        try modelContext.delete(model: ShowRecentListening.self)
        try modelContext.delete(model: ListeningLoadedDiscState.self)
        try modelContext.delete(model: ShowWantsLiveSong.self)
        try modelContext.delete(model: ShowArtistListeningPreference.self)
        try modelContext.delete(model: ShowOpeningFamiliarityBaseline.self)
        try modelContext.delete(model: ShowOpeningArtistTier.self)
        try modelContext.delete(model: ShowSetlistMemory.self)
        try modelContext.delete(model: SongFamiliarityRecord.self)
        try modelContext.delete(model: ArtistCatalogSnapshot.self)
        try modelContext.delete(model: CatalogSong.self)
        try modelContext.delete(model: CatalogAlbum.self)
    }
}
