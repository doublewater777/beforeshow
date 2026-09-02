import Foundation

/// Retry journal for ticket/timetable files only. Memory-fragment cleanup keeps
/// the implementation from `main` and deliberately does not use this type.
enum ShowAssetCleanupRetry {
    struct PendingAsset: Codable, Equatable {
        let showID: UUID
        let kind: ShowAssetKind
        let relativePath: String
    }

    struct PendingDynamicCover: Codable, Equatable {
        let showID: UUID
        let relativePath: String
    }

    private static let pendingFullCleanupKey = "BeforeShow.pendingFullShowAssetMediaCleanup"
    private static let pendingDynamicCoverCleanupKey = "BeforeShow.pendingDynamicCoverMediaCleanup"
    private static let preparedFullCleanupKey = "BeforeShow.preparedShowAssetCleanup"
    // Keep the pre-split ticket markers readable so an interrupted ticket-only
    // cleanup from an earlier build is still recovered after this refactor.
    private static let pendingShowCleanupKey = "BeforeShow.pendingShowMediaCleanup"
    private static let pendingAssetCleanupKey = "BeforeShow.pendingAssetMediaCleanup"

    static var isFullCleanupPending: Bool {
        UserDefaults.standard.bool(forKey: pendingFullCleanupKey)
    }

    static var isFullCleanupPrepared: Bool {
        UserDefaults.standard.bool(forKey: preparedFullCleanupKey)
    }

    static func markFullCleanupPrepared() {
        UserDefaults.standard.set(true, forKey: preparedFullCleanupKey)
        UserDefaults.standard.synchronize()
    }

    static func clearFullCleanupPrepared() {
        UserDefaults.standard.removeObject(forKey: preparedFullCleanupKey)
    }

    static func markFullCleanupPending() {
        UserDefaults.standard.set(true, forKey: pendingFullCleanupKey)
        UserDefaults.standard.synchronize()
    }

    static func clearFullCleanupPending() {
        UserDefaults.standard.removeObject(forKey: pendingFullCleanupKey)
    }

    static var pendingShowCleanupIDs: [UUID] {
        let rawValues = UserDefaults.standard.stringArray(forKey: pendingShowCleanupKey) ?? []
        return rawValues.compactMap(UUID.init(uuidString:))
    }

    static func markShowCleanupPending(_ showID: UUID) {
        var ids = Set(pendingShowCleanupIDs.map(\.uuidString))
        ids.insert(showID.uuidString)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: pendingShowCleanupKey)
    }

    static func clearShowCleanupPending(_ showID: UUID) {
        let remaining = pendingShowCleanupIDs
            .filter { $0 != showID }
            .map(\.uuidString)
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingShowCleanupKey)
        } else {
            UserDefaults.standard.set(remaining, forKey: pendingShowCleanupKey)
        }
    }

    static var pendingAssets: [PendingAsset] {
        guard let data = UserDefaults.standard.data(forKey: pendingAssetCleanupKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingAsset].self, from: data)) ?? []
    }

    static func markAssetCleanupPending(
        showID: UUID,
        kind: ShowAssetKind,
        relativePath: String
    ) {
        guard ShowAsset.isValidRelativePath(relativePath, showID: showID, kind: kind) else { return }
        let pending = PendingAsset(showID: showID, kind: kind, relativePath: relativePath)
        var values = pendingAssets
        if !values.contains(pending) {
            values.append(pending)
            persistAssets(values)
        }
    }

    static func clearAssetCleanupPending(_ pending: PendingAsset) {
        persistAssets(pendingAssets.filter { $0 != pending })
    }

    static var pendingDynamicCovers: [PendingDynamicCover] {
        guard let data = UserDefaults.standard.data(forKey: pendingDynamicCoverCleanupKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingDynamicCover].self, from: data)) ?? []
    }

    static func markDynamicCoverCleanupPending(showID: UUID, relativePath: String) {
        guard DynamicCover.isValidRelativePath(relativePath, showID: showID) else { return }
        let pending = PendingDynamicCover(showID: showID, relativePath: relativePath)
        var values = pendingDynamicCovers
        if !values.contains(pending) {
            values.append(pending)
            persistDynamicCovers(values)
        }
    }

    static func clearDynamicCoverCleanupPending(_ pending: PendingDynamicCover) {
        persistDynamicCovers(pendingDynamicCovers.filter { $0 != pending })
    }

    private static func persistDynamicCovers(_ values: [PendingDynamicCover]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingDynamicCoverCleanupKey)
            return
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingDynamicCoverCleanupKey)
        }
    }

    private static func persistAssets(_ values: [PendingAsset]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingAssetCleanupKey)
            return
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingAssetCleanupKey)
        }
    }
}
