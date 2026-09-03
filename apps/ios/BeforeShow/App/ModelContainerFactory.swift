import SwiftData

enum ModelContainerFactory {
    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            NotificationSchedulingState.self,
            ShowNotificationScheduleRecord.self,
            MemoryFragment.self,
            MemoryMediaItem.self,
            ShowAsset.self,
            DynamicCover.self,
            ArtistCatalogSnapshot.self,
            CatalogSong.self,
            CatalogAlbum.self,
            SongFamiliarityRecord.self,
            ShowWantsLiveSong.self,
            ShowArtistListeningPreference.self,
            ShowOpeningFamiliarityBaseline.self,
            ShowOpeningArtistTier.self,
            ShowSetlistMemory.self,
            configurations: configuration
        )
    }
}
