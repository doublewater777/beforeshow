import Foundation
import SwiftData

struct LocalDataInventory: Equatable {
    var showCount = 0
    var memoryFragmentCount = 0
    var assetCount = 0
    var dynamicCoverCount = 0
    var familiarSongCount = 0
    var wantsLiveCount = 0
    var setlistMemoryCount = 0
    var listeningCatalogItemCount = 0
    var listeningRecordCount = 0
    var appBytes: Int64 = 0
    var mediaBytes: Int64 = 0

    var isEmpty: Bool {
        showCount == 0
            && memoryFragmentCount == 0
            && assetCount == 0
            && dynamicCoverCount == 0
            && listeningRecordCount == 0
            && mediaBytes == 0
    }
}

@MainActor
enum LocalDataInventoryService {
    static func compute(modelContext: ModelContext) async -> LocalDataInventory {
        var inventory = LocalDataInventory()
        inventory.showCount = count(Show.self, in: modelContext)
        inventory.memoryFragmentCount = count(MemoryFragment.self, in: modelContext)
        inventory.assetCount = count(ShowAsset.self, in: modelContext)
        inventory.dynamicCoverCount = count(DynamicCover.self, in: modelContext)
        inventory.familiarSongCount = count(SongFamiliarityRecord.self, in: modelContext)
        inventory.wantsLiveCount = count(ShowWantsLiveSong.self, in: modelContext)
        inventory.setlistMemoryCount = count(ShowSetlistMemory.self, in: modelContext)
        inventory.listeningCatalogItemCount = count(ArtistCatalogSnapshot.self, in: modelContext)
            + count(CatalogSong.self, in: modelContext)
            + count(CatalogAlbum.self, in: modelContext)
        inventory.listeningRecordCount = inventory.familiarSongCount
            + inventory.wantsLiveCount
            + inventory.setlistMemoryCount
            + inventory.listeningCatalogItemCount
            + count(ShowArtistListeningPreference.self, in: modelContext)
            + count(ShowOpeningFamiliarityBaseline.self, in: modelContext)
            + count(ShowOpeningArtistTier.self, in: modelContext)

        inventory.appBytes = directoryBytes(at: URL(fileURLWithPath: NSHomeDirectory()))

        var bytes: Int64 = 0
        bytes += directoryBytes(at: await ShowAssetMediaStore.shared.rootDirectoryURL())
        bytes += directoryBytes(at: await DynamicCoverMediaStore.shared.rootDirectoryURL())
        bytes += directoryBytes(at: MemoryFragmentMediaStore.shared.location.rootDirectory)
        inventory.mediaBytes = bytes
        return inventory
    }

    private static func count<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    static func directoryBytes(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
