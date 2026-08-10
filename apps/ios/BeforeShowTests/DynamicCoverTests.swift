import XCTest
import SwiftData
@testable import BeforeShow

final class DynamicCoverTests: XCTestCase {
    func testDynamicFaceStorePersistsPerShowAndClears() {
        let defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        let first = UUID()
        let second = UUID()

        DynamicCoverFaceStore.setDynamicFace(true, for: first, defaults: defaults)
        XCTAssertTrue(DynamicCoverFaceStore.isDynamicFace(for: first, defaults: defaults))
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: second, defaults: defaults))

        DynamicCoverFaceStore.clear(showID: first, defaults: defaults)
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: first, defaults: defaults))
        defaults.removePersistentDomain(forName: #file)
    }

    func testDynamicCoverPathStaysBoundToShowDirectory() {
        let showID = UUID()
        XCTAssertTrue(DynamicCover.isValidRelativePath("\(showID.uuidString)/video.mov", showID: showID))
        XCTAssertFalse(DynamicCover.isValidRelativePath("other/video.mov", showID: showID))
        XCTAssertFalse(DynamicCover.isValidRelativePath("\(showID.uuidString)/../video.mov", showID: showID))
    }

    func testDynamicCoverStagingCleanupRemovesOnlyExpiredDrafts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicCoverTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DynamicCoverMediaStore(location: DynamicCoverMediaLocation(rootDirectory: root))
        let staleDraft = root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        let freshDraft = root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staleDraft, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: freshDraft, withIntermediateDirectories: true)
        try Data([1]).write(to: staleDraft.appendingPathComponent("stale.mov"))
        try Data([1]).write(to: freshDraft.appendingPathComponent("fresh.mov"))
        let staleDate = Date().addingTimeInterval(-86_401)
        try FileManager.default.setAttributes(
            [.modificationDate: staleDate],
            ofItemAtPath: staleDraft.path
        )

        try await store.cleanupStaging(olderThan: Date().addingTimeInterval(-86_400))

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDraft.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshDraft.path))
    }

    @MainActor
    func testFullCleanupRetryKeepsMarkerUntilBothMediaStoresSucceed() async {
        ShowAssetCleanupRetry.clearFullCleanupPending()
        ShowAssetCleanupRetry.markFullCleanupPending()
        defer { ShowAssetCleanupRetry.clearFullCleanupPending() }

        var showAssetAttempts = 0
        var dynamicCoverAttempts = 0
        await retryPendingFullCleanup(
            deleteShowAssets: {
                showAssetAttempts += 1
            },
            deleteDynamicCovers: {
                dynamicCoverAttempts += 1
                throw DynamicCoverMediaStoreError.storageUnavailable
            }
        )

        XCTAssertEqual(showAssetAttempts, 1)
        XCTAssertEqual(dynamicCoverAttempts, 1)
        XCTAssertTrue(ShowAssetCleanupRetry.isFullCleanupPending)

        await retryPendingFullCleanup(
            deleteShowAssets: {
                showAssetAttempts += 1
            },
            deleteDynamicCovers: {
                dynamicCoverAttempts += 1
            }
        )

        XCTAssertEqual(showAssetAttempts, 2)
        XCTAssertEqual(dynamicCoverAttempts, 2)
        XCTAssertFalse(ShowAssetCleanupRetry.isFullCleanupPending)
    }

    @MainActor
    func testReconcileMissingCurrentCoverClearsFacePreference() throws {
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let show = try Show(name: "失效动态封面", date: Date(), startTime: Date())
        let cover = DynamicCover(
            showID: show.id,
            relativePath: "\(show.id.uuidString)/missing.mov",
            contentTypeIdentifier: "public.movie",
            videoDuration: 1
        )
        cover.show = show
        show.dynamicCover = cover
        container.mainContext.insert(show)
        container.mainContext.insert(cover)
        try container.mainContext.save()

        DynamicCoverFaceStore.setDynamicFace(true, for: show.id)
        _ = try reconcileDynamicCoverModelBoundary(
            in: container.mainContext,
            existingRelativePaths: []
        )

        XCTAssertNil(show.dynamicCover)
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: show.id))
    }
}
