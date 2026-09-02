import Foundation

extension DynamicCoverMediaStore {
    func finalizeCommit(draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    func rollbackCommittedFile(relativePath: String) throws {
        try removeIfPresent(location.url(for: relativePath))
        try removeIfPresent(location.url(for: Self.posterRelativePath(forVideoRelativePath: relativePath)))
    }

    func discardDraft(_ draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    func discardImportedFile(_ imported: DynamicCoverImportedFile) throws {
        try removeIfPresent(imported.url)
    }

    func delete(relativePath: String, showID: UUID) throws {
        guard DynamicCover.isValidRelativePath(relativePath, showID: showID) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        try removeIfPresent(location.url(for: relativePath))
        try removeIfPresent(location.url(for: Self.posterRelativePath(forVideoRelativePath: relativePath)))
    }

    func deleteShow(_ showID: UUID) throws {
        try ensureStorageAvailable()
        try removeIfPresent(location.rootDirectory.appendingPathComponent(showID.uuidString, isDirectory: true))
    }

    func deleteAll() throws {
        try ensureStorageAvailable()
        try removeIfPresent(location.rootDirectory)
    }

    func cleanupStaging(olderThan cutoff: Date) throws {
        let staging = location.url(for: "Staging")
        guard fileManager.fileExists(atPath: staging.path) else { return }
        for directory in try fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            let values = try directory.resourceValues(forKeys: [.contentModificationDateKey])
            if values.contentModificationDate.map({ $0 < cutoff }) ?? true {
                try removeIfPresent(directory)
            }
        }
    }

    func cleanupImportTemp(olderThan cutoff: Date) throws {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("BeforeShowDynamicCoverImports", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for fileURL in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            if values.contentModificationDate.map({ $0 < cutoff }) ?? true {
                try removeIfPresent(fileURL)
            }
        }
    }

    /// Keeps only paths referenced by valid `DynamicCover` records.
    func verifiedExistingRelativePaths() throws -> Set<String> {
        try ensureStorageAvailable()
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        guard let enumerator = fileManager.enumerator(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        var paths = Set<String>()
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = try Self.relativePath(for: fileURL, under: location.rootDirectory)
            guard !relativePath.hasPrefix("Staging/") else { continue }
            paths.insert(relativePath)
        }
        return paths
    }

    func reconcile(validRelativePaths: Set<String>) throws {
        try ensureStorageAvailable()
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        guard let enumerator = fileManager.enumerator(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = try Self.relativePath(for: fileURL, under: location.rootDirectory)
            guard !relativePath.hasPrefix("Staging/"), !validRelativePaths.contains(relativePath) else { continue }
            try removeIfPresent(fileURL)
        }
        try pruneEmptyDirectories()
    }

    private func pruneEmptyDirectories() throws {
        guard fileManager.fileExists(atPath: location.rootDirectory.path),
              let enumerator = fileManager.enumerator(
                at: location.rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let directories = enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.path.count > $1.path.count }
        for directory in directories where directory.lastPathComponent != "Staging" {
            if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
                try? removeIfPresent(directory)
            }
        }
    }
}
