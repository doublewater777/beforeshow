import Foundation

extension DynamicCoverMediaStore {
    func ensureStorageAvailable() throws {
        if let storageError { throw storageError }
    }

    func prepareRootDirectory() throws {
        do {
            try fileManager.createDirectory(at: location.rootDirectory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var root = location.rootDirectory
            try root.setResourceValues(values)
        } catch {
            throw DynamicCoverMediaStoreError.map(error)
        }
    }

    func replaceItem(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var destination = destination
            try destination.setResourceValues(values)
        } catch {
            try? removeIfPresent(destination)
            throw DynamicCoverMediaStoreError.map(error)
        }
    }

    func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Poster files live next to their video as `<video name>-poster.jpg` so
    /// delete/reconcile can derive them without extra persisted state.
    nonisolated static func posterRelativePath(forVideoRelativePath relativePath: String) -> String {
        "\((relativePath as NSString).deletingPathExtension)-poster.jpg"
    }
}
