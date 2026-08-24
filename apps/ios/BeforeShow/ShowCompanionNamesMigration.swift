import Foundation
import SwiftData

/// 启动时，将旧版本的 `companionName: String?` 单值字段
/// 一次性迁移落库到 `companionNamesStored: [String]` 数组中。
enum ShowCompanionNamesMigration {
    static func migrateIfNeeded(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }

        guard migrateUnresolvedCompanionNames(in: shows) else { return }
        try? modelContext.save()
    }

    @discardableResult
    static func migrateUnresolvedCompanionNames(in shows: [Show]) -> Bool {
        var didChange = false
        for show in shows where show.hasUnresolvedCompanionNames {
            if let legacy = show.companionName {
                show.companionNames = [legacy]
                didChange = true
            }
        }
        return didChange
    }
}
