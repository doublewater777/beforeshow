import Foundation

/// Local store for a single optional video per show.
/// Files are staged before SwiftData saves and remain show-scoped for reconciliation.
actor DynamicCoverMediaStore {
    static let shared: DynamicCoverMediaStore = {
        do {
            return DynamicCoverMediaStore(location: try DynamicCoverMediaLocation.applicationSupport())
        } catch {
            return DynamicCoverMediaStore(storageError: .storageUnavailable)
        }
    }()

    let location: DynamicCoverMediaLocation
    let fileManager: FileManager
    let storageError: DynamicCoverMediaStoreError?

    init(location: DynamicCoverMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
        self.storageError = nil
    }

    init(storageError: DynamicCoverMediaStoreError, fileManager: FileManager = .default) {
        self.location = DynamicCoverMediaLocation(
            rootDirectory: fileManager.temporaryDirectory.appendingPathComponent(
                "UnavailableDynamicCovers",
                isDirectory: true
            )
        )
        self.fileManager = fileManager
        self.storageError = storageError
    }

    func rootDirectoryURL() -> URL {
        location.rootDirectory
    }

    func acquireCommitGate() async {
        await LocalMediaCommitGate.shared.acquire()
    }

    func releaseCommitGate() async {
        await LocalMediaCommitGate.shared.release()
    }

    func absoluteURL(for relativePath: String) -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            return location.rootDirectory.appendingPathComponent("__invalid-relative-path__")
        }
        return location.url(for: relativePath)
    }

    func absoluteURL(for relativePath: String, showID: UUID) throws -> URL {
        guard DynamicCover.isValidRelativePath(relativePath, showID: showID) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        return absoluteURL(for: relativePath)
    }

    func ensureAvailable() throws {
        try ensureStorageAvailable()
    }

    /// FileManager can expose the same sandbox through aliased paths (for
    /// example `/var` vs `/private/var`). Normalize both URLs before deriving
    /// a persisted relative path so reconciliation does not discard a valid
    /// dynamic cover after relaunch.
    nonisolated static func relativePath(for fileURL: URL, under rootDirectory: URL) throws -> String {
        let root = rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        let file = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = root.pathComponents
        let fileComponents = file.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }

        let relativePath = fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
        guard isSafeRelativePath(relativePath) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        return relativePath
    }

    nonisolated private static func isSafeRelativePath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        return !components.isEmpty
            && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
}
