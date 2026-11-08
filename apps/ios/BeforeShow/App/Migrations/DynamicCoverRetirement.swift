import Foundation
import SwiftData

/// 动态封面已下线。旧版本留下的记录、视频副本和翻面状态启动时清一次；
/// `DynamicCover` 模型与 `Show.dynamicCover` 只为让旧数据库能打开而保留。
/// 保存失败不落标记，下次启动再试。
@MainActor
enum DynamicCoverRetirement {
    static let completedKey = "dynamic-cover.retired.v1"
    static let pendingCleanupKey = "BeforeShow.pendingDynamicCoverMediaCleanup"
    static let faceKeyPrefix = "dynamic-cover-face-v1-"

    static func retireIfNeeded(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard !defaults.bool(forKey: completedKey),
              let covers = try? modelContext.fetch(FetchDescriptor<DynamicCover>()) else { return }
        if !covers.isEmpty {
            for cover in covers {
                cover.show?.dynamicCover = nil
                modelContext.delete(cover)
            }
            do { try modelContext.save() } catch {
                modelContext.rollback()
                return
            }
        }
        for directory in mediaDirectories(fileManager: fileManager) where fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }
        defaults.removeObject(forKey: pendingCleanupKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(faceKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: completedKey)
    }

    static func mediaDirectories(fileManager: FileManager) -> [URL] {
        var directories = [fileManager.temporaryDirectory.appendingPathComponent("BeforeShowDynamicCoverImports", isDirectory: true)]
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            directories.append(support.appendingPathComponent("DynamicCovers", isDirectory: true))
        }
        return directories
    }
}
