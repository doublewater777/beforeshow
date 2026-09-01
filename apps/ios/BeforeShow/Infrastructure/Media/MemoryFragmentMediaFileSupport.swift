import Foundation

extension MemoryFragmentMediaStore {
    func ensureAvailableCapacity(forByteCount required: Int64) throws {
        guard required > 0 else { return }
        let values = try location.rootDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < required {
            throw MemoryMediaStoreError.insufficientDiskSpace
        }
    }

    func createParentDirectory(for url: URL) throws {
        try prepareRootDirectory()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func prepareRootDirectory() throws {
        try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = location.rootDirectory
        try root.setResourceValues(values)
    }

    func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
