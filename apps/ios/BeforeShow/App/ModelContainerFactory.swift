import SwiftData

enum ModelContainerFactory {
    static let models: [any PersistentModel.Type] = [
        Show.self,
        CurrentShowSelection.self,
        NotificationSchedulingState.self,
        ShowNotificationScheduleRecord.self,
        MemoryFragment.self,
        MemoryMediaItem.self,
        ShowAsset.self,
        Timetable.self,
        TimetableDay.self,
        TimetableStage.self,
        TimetablePerformance.self,
        DynamicCover.self,
        ArtistCatalogSnapshot.self,
        CatalogSong.self,
        CatalogAlbum.self,
        SongFamiliarityRecord.self,
        ShowRecentListening.self,
        ListeningLoadedDiscState.self,
        ShowArtistListeningPreference.self,
        ShowOpeningFamiliarityBaseline.self,
        ShowOpeningArtistTier.self,
        ShowSetlistMemory.self,
        FeatureRecommendationRecord.self,
    ]

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        try make(configuration: ModelConfiguration(
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        ))
    }

    static func make(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: configuration)
    }
}
