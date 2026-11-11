import Foundation

/// Tickets, timetables, merch photos and memories used to be kept out of iCloud and computer backups, so a restored
/// phone came back with the records but not the pictures. New files are backed up; this lets the older ones back in,
/// once. A file it cannot change leaves the step to run again next launch.
@MainActor
enum MediaBackupInclusion {
    static let completedKey = "media-backup-included.v1"

    static func includeIfNeeded(defaults: UserDefaults = .standard, roots: [URL]? = nil) async {
        guard !defaults.bool(forKey: completedKey) else { return }
        let roots = roots ?? defaultRoots()
        let included = await Task.detached(priority: .utility) { include(roots) }.value
        if included { defaults.set(true, forKey: completedKey) }
    }

    private static func defaultRoots() -> [URL] {
        [try? ShowAssetMediaLocation.applicationSupport().rootDirectory, MemoryMediaLocation.applicationSupport().rootDirectory]
            .compactMap { $0 }
    }

    private nonisolated static func include(_ roots: [URL]) -> Bool {
        let fileManager = FileManager.default
        var included = true
        for root in roots where fileManager.fileExists(atPath: root.path) {
            let inside = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            for var url in [root] + inside {
                var values = URLResourceValues()
                values.isExcludedFromBackup = false
                do { try url.setResourceValues(values) } catch { included = false }
            }
        }
        return included
    }
}
