import Foundation

extension MemoryFragmentMediaStore {
    func deleteFiles(relativePaths: [String]) throws {
        for path in relativePaths {
            try removeIfPresent(location.url(for: path))
        }
    }

    func discardDraft(_ draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    /// Removes a transferred temporary file when cancellation happens before staging owns it.
    func discardImportedFile(_ imported: MemoryImportedFile) throws {
        try removeIfPresent(imported.url)
    }

    /// Removes a single staged item's original and thumbnail from the staging
    /// directory. Called when the user removes a draft item from the composer so the
    /// 20-item limit reflects real staged files instead of leaving orphan staging
    /// behind (which previously let "import -> delete -> reimport" bypass the cap).
    func removeStagedItem(_ item: MemoryDraftMedia) throws {
        try removeIfPresent(location.url(for: item.stagedRelativePath))
        if let thumbnail = item.thumbnailStagedRelativePath {
            try removeIfPresent(location.url(for: thumbnail))
        }
    }

    func deleteFragment(showID: UUID, fragmentID: UUID) throws {
        try removeIfPresent(location.url(for: "\(showID.uuidString)/\(fragmentID.uuidString)"))
    }

    func deleteShow(_ showID: UUID) throws {
        try removeIfPresent(location.url(for: showID.uuidString))
    }

    func deleteAll() throws {
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

    /// Removes stale files left in the PhotosPicker transfer temp directory
    /// (`BeforeShowMemoryImports`). The picker copies each selected file here before
    /// the store is involved, and a failed/cancelled import can leave files behind
    /// that memory reconciliation (which scans the memory root, not this temp dir)
    /// would never reclaim.
    func cleanupImportTemp(olderThan cutoff: Date) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
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

    /// Removes unreferenced files inside valid fragment directories and orphan fragment directories.
    func reconcileFragmentFiles(
        showID: UUID,
        validFilesByFragmentID: [UUID: Set<String>]
    ) throws {
        let showDirectory = location.url(for: showID.uuidString)
        guard fileManager.fileExists(atPath: showDirectory.path) else { return }

        for directory in try fileManager.contentsOfDirectory(
            at: showDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            guard let fragmentID = UUID(uuidString: directory.lastPathComponent) else {
                try removeIfPresent(directory)
                continue
            }

            guard let validRelativePaths = validFilesByFragmentID[fragmentID] else {
                try removeIfPresent(directory)
                continue
            }

            let validFileNames = Set(validRelativePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
            for fileURL in try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) where !validFileNames.contains(fileURL.lastPathComponent) {
                try removeIfPresent(fileURL)
            }
        }
    }

    /// App-wide recovery: remove orphan show/fragment dirs and unreferenced files.
    func reconcileAll(validFilesByShowAndFragment: [UUID: [UUID: Set<String>]]) throws {
        guard fileManager.fileExists(atPath: location.rootDirectory.path) else { return }
        for showDirectory in try fileManager.contentsOfDirectory(
            at: location.rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            let name = showDirectory.lastPathComponent
            if name == "Staging" {
                continue
            }
            guard let showID = UUID(uuidString: name) else {
                try removeIfPresent(showDirectory)
                continue
            }
            guard let fragments = validFilesByShowAndFragment[showID] else {
                try removeIfPresent(showDirectory)
                continue
            }
            try reconcileFragmentFiles(showID: showID, validFilesByFragmentID: fragments)
        }
    }
}
