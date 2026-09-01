import Foundation

extension MemoryFragmentMediaStore {
    func commit(draftID: UUID, showID: UUID, fragmentID: UUID, media: [MemoryDraftMedia]) throws -> [MemoryCommittedMedia] {
        let finalRelativeDirectory = "\(showID.uuidString)/\(fragmentID.uuidString)"
        let finalDirectory = location.url(for: finalRelativeDirectory)
        return try copyStagingToFinal(
            draftID: draftID,
            finalRelativeDirectory: finalRelativeDirectory,
            finalDirectory: finalDirectory,
            media: media,
            replaceExistingDirectory: true
        )
    }

    func commitAdditions(
        draftID: UUID,
        showID: UUID,
        fragmentID: UUID,
        media: [MemoryDraftMedia]
    ) throws -> [MemoryCommittedMedia] {
        let finalRelativeDirectory = "\(showID.uuidString)/\(fragmentID.uuidString)"
        let finalDirectory = location.url(for: finalRelativeDirectory)
        return try copyStagingToFinal(
            draftID: draftID,
            finalRelativeDirectory: finalRelativeDirectory,
            finalDirectory: finalDirectory,
            media: media,
            replaceExistingDirectory: false
        )
    }

    /// Call only after SwiftData successfully persisted the committed media.
    func finalizeCommit(draftID: UUID) throws {
        try removeIfPresent(location.url(for: "Staging/\(draftID.uuidString)"))
    }

    /// Call when SwiftData failed after files were copied to the final location.
    func rollbackCommittedFiles(relativePaths: [String]) throws {
        try deleteFiles(relativePaths: relativePaths)
    }

    private func copyStagingToFinal(
        draftID: UUID,
        finalRelativeDirectory: String,
        finalDirectory: URL,
        media: [MemoryDraftMedia],
        replaceExistingDirectory: Bool
    ) throws -> [MemoryCommittedMedia] {
        let stagedDirectory = location.url(for: "Staging/\(draftID.uuidString)")
        guard fileManager.fileExists(atPath: stagedDirectory.path) else {
            throw MemoryMediaStoreError.missingStagedDraft
        }

        try fileManager.createDirectory(
            at: finalDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if replaceExistingDirectory, fileManager.fileExists(atPath: finalDirectory.path) {
            try fileManager.removeItem(at: finalDirectory)
        }
        try fileManager.createDirectory(at: finalDirectory, withIntermediateDirectories: true)

        var committed: [MemoryCommittedMedia] = []
        var copiedURLs: [URL] = []
        do {
            for item in media {
                let source = location.url(for: item.stagedRelativePath)
                guard fileManager.fileExists(atPath: source.path) else {
                    throw MemoryMediaStoreError.missingStagedDraft
                }
                let relativePath = "\(finalRelativeDirectory)/\(source.lastPathComponent)"
                let destination = location.url(for: relativePath)
                let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                try ensureAvailableCapacity(forByteCount: sourceSize)
                try replaceItem(at: destination, with: source)
                copiedURLs.append(destination)

                var thumbnailRelativePath: String?
                if let stagedThumbnail = item.thumbnailStagedRelativePath {
                    let thumbnailSource = location.url(for: stagedThumbnail)
                    guard fileManager.fileExists(atPath: thumbnailSource.path) else {
                        throw MemoryMediaStoreError.missingStagedDraft
                    }
                    let thumbnailPath = "\(finalRelativeDirectory)/\(thumbnailSource.lastPathComponent)"
                    let thumbnailDestination = location.url(for: thumbnailPath)
                    let thumbSize = (try? thumbnailSource.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    try ensureAvailableCapacity(forByteCount: thumbSize)
                    try replaceItem(at: thumbnailDestination, with: thumbnailSource)
                    copiedURLs.append(thumbnailDestination)
                    thumbnailRelativePath = thumbnailPath
                }

                committed.append(MemoryCommittedMedia(
                    id: item.id,
                    kind: item.kind,
                    relativePath: relativePath,
                    thumbnailRelativePath: thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration
                ))
            }
            // Keep staging until SwiftData save succeeds so failed saves remain retryable.
            return committed
        } catch {
            for copiedURL in copiedURLs {
                try? removeIfPresent(copiedURL)
            }
            throw error
        }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw MemoryMediaStoreError.map(error)
        }
    }
}
