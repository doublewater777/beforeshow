import Foundation
import SwiftData

struct LocalDataInventory: Equatable {
    var showCount = 0
    var memoryFragmentCount = 0
    var assetCount = 0
    var dynamicCoverCount = 0
    var appBytes: Int64 = 0
    var mediaBytes: Int64 = 0

    var isEmpty: Bool {
        showCount == 0 && memoryFragmentCount == 0 && assetCount == 0 && dynamicCoverCount == 0 && mediaBytes == 0
    }
}

@MainActor
enum LocalDataInventoryService {
    static func compute(modelContext: ModelContext) async -> LocalDataInventory {
        var inventory = LocalDataInventory()
        inventory.showCount = (try? modelContext.fetchCount(FetchDescriptor<Show>())) ?? 0
        inventory.memoryFragmentCount = (try? modelContext.fetchCount(FetchDescriptor<MemoryFragment>())) ?? 0
        inventory.assetCount = (try? modelContext.fetchCount(FetchDescriptor<ShowAsset>())) ?? 0
        inventory.dynamicCoverCount = (try? modelContext.fetchCount(FetchDescriptor<DynamicCover>())) ?? 0

        inventory.appBytes = directoryBytes(at: URL(fileURLWithPath: NSHomeDirectory()))

        var bytes: Int64 = 0
        bytes += directoryBytes(at: await ShowAssetMediaStore.shared.rootDirectoryURL())
        bytes += directoryBytes(at: await DynamicCoverMediaStore.shared.rootDirectoryURL())
        bytes += directoryBytes(at: MemoryFragmentMediaStore.shared.location.rootDirectory)
        inventory.mediaBytes = bytes
        return inventory
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
