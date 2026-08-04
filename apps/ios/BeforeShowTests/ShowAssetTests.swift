import SwiftData
import UIKit
import XCTest
@testable import BeforeShow

@MainActor
final class ShowAssetTests: XCTestCase {
    func testKindCopyMatchesProductLanguage() {
        XCTAssertEqual(ShowAssetKind.ticket.title, "票根")
        XCTAssertEqual(ShowAssetKind.timetable.title, "时刻表")
        XCTAssertEqual(ShowAssetKind.ticket.viewerTitle, "我的票根")
        XCTAssertEqual(ShowAssetKind.timetable.viewerTitle, "时刻表")
        XCTAssertEqual(ShowAssetKind.ticket.emptySubtitle, "未添加")
        XCTAssertEqual(ShowAssetKind.ticket.savedSubtitle, "已保存")
    }

    func testMediaStoreSavesAndDeletesShowScopedFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowAssetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShowAssetMediaStore(location: ShowAssetMediaLocation(rootDirectory: root))
        let showID = UUID()
        let data = try XCTUnwrap(solidJPEGData())

        let relativePath = try await store.saveImage(
            data: data,
            showID: showID,
            kind: .ticket,
            assetID: UUID()
        )
        let absolute = await store.absoluteURL(for: relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: absolute.path))
        let fileValues = try absolute.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(fileValues.isExcludedFromBackup, true)
        XCTAssertTrue(relativePath.contains(showID.uuidString))
        XCTAssertTrue(relativePath.contains(ShowAssetKind.ticket.directoryName))
        let rootURL = await store.rootDirectoryURL()
        let resourceValues = try rootURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)

        try await store.deleteShow(showID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: absolute.path))
    }

    func testReconcileDropsOrphanFilesAndKeepsReferenced() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowAssetReconcile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShowAssetMediaStore(location: ShowAssetMediaLocation(rootDirectory: root))
        let showID = UUID()
        let data = try XCTUnwrap(solidJPEGData())

        let kept = try await store.saveImage(data: data, showID: showID, kind: .ticket)
        let orphan = try await store.saveImage(data: data, showID: showID, kind: .timetable)

        try await store.reconcile(validRelativePaths: [kept])
        let keptURL = await store.absoluteURL(for: kept)
        let orphanURL = await store.absoluteURL(for: orphan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func testAssetShowBoundaryRemovesOrphansAndBackfillsRelationship() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            ShowAsset.self,
            configurations: configuration
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "票根现场", date: now, startTime: now)
        context.insert(show)

        // Create the on-disk file so boundary reconcile keeps the linked asset.
        let relativePath = "\(show.id.uuidString)/ticket/a.jpg"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowAssetBoundary-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xFF, 0xD8, 0xFF]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let linked = ShowAsset(
            showID: show.id,
            kind: .ticket,
            relativePath: relativePath
        )
        // Simulate pre-relationship production data: showID present, relationship nil.
        context.insert(linked)

        let orphan = ShowAsset(
            showID: UUID(),
            kind: .timetable,
            relativePath: "missing/timetable/b.jpg"
        )
        context.insert(orphan)
        try context.save()

        let valid = try reconcileShowAssetShowBoundary(in: context, assetRootDirectory: root)
        XCTAssertEqual(valid, [linked.relativePath])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShowAsset>()).count, 1)
        XCTAssertEqual(linked.show?.id, show.id)
    }

    func testShowDeletionCascadeRemovesAssetRecords() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            ShowAsset.self,
            configurations: configuration
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "时刻表现场", date: now, startTime: now)
        context.insert(show)

        let asset = ShowAsset(
            showID: show.id,
            kind: .timetable,
            relativePath: "\(show.id.uuidString)/timetable/a.jpg"
        )
        asset.show = show
        context.insert(asset)
        try context.save()

        context.delete(show)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowAsset>()).isEmpty)
    }

    func testRollbackHelperClearsDirtyContextWhenSaveFails() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            ShowAsset.self,
            configurations: configuration
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "票根现场", date: now, startTime: now)
        context.insert(show)
        let linked = ShowAsset(
            showID: show.id,
            kind: .ticket,
            relativePath: "\(show.id.uuidString)/ticket/original.jpg"
        )
        linked.show = show
        context.insert(linked)
        try context.save()

        let originalPath = linked.relativePath
        linked.replaceImage(relativePath: "\(show.id.uuidString)/ticket/dirty.jpg")
        XCTAssertTrue(context.hasChanges)

        XCTAssertThrowsError(
            try saveModelContextRollingBackOnFailure(context) {
                struct ForcedSaveError: Error {}
                throw ForcedSaveError()
            }
        )
        XCTAssertFalse(context.hasChanges)

        let verificationContext = ModelContext(container)
        let fetched = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<ShowAsset>()).first
        )
        XCTAssertEqual(fetched.relativePath, originalPath)
    }


    func testSaveImageUsesVersionedPathsAndKeepsBothCandidatesUntilCallerDeletes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowAssetVersionedPath-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShowAssetMediaStore(location: ShowAssetMediaLocation(rootDirectory: root))
        let showID = UUID()
        let data = try XCTUnwrap(solidJPEGData())

        let first = try await store.saveImage(data: data, showID: showID, kind: .ticket, assetID: UUID())
        let second = try await store.saveImage(data: data, showID: showID, kind: .ticket, assetID: UUID())
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("/ticket/"))
        XCTAssertTrue(second.contains("/ticket/"))
        let firstURL = await store.absoluteURL(for: first)
        let secondURL = await store.absoluteURL(for: second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testCommitGateSerializesConcurrentAccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowAssetCommitGate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShowAssetMediaStore(location: ShowAssetMediaLocation(rootDirectory: root))

        await store.acquireCommitGate()
        let secondAcquired = BooleanBox()
        let waiter = Task<Void, Never> {
            await store.acquireCommitGate()
            await secondAcquired.setTrue()
            await store.releaseCommitGate()
        }
        try await Task.sleep(for: .milliseconds(60))
        let wasAcquiredBeforeRelease = await secondAcquired.get()
        XCTAssertFalse(wasAcquiredBeforeRelease, "Second acquire must block while the gate is held")
        await store.releaseCommitGate()
        await waiter.value
        let wasAcquiredAfterRelease = await secondAcquired.get()
        XCTAssertTrue(wasAcquiredAfterRelease, "Second acquire completes once the gate is released")
    }

    func testTicketAndMemoryStoresShareCommitGate() async throws {
        let ticketStore = ShowAssetMediaStore(location: ShowAssetMediaLocation(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShowAssetSharedGate-\(UUID().uuidString)", isDirectory: true)
        ))
        await ticketStore.acquireCommitGate()

        let memoryStore = MemoryFragmentMediaStore(location: MemoryMediaLocation(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MemorySharedGate-\(UUID().uuidString)", isDirectory: true)
        ))
        let acquired = BooleanBox()
        let waiter = Task {
            await memoryStore.acquireCommitGate()
            await acquired.setTrue()
            await memoryStore.releaseCommitGate()
        }

        try await Task.sleep(for: .milliseconds(60))
        let wasAcquiredBeforeRelease = await acquired.get()
        XCTAssertFalse(wasAcquiredBeforeRelease)
        await ticketStore.releaseCommitGate()
        await waiter.value
        let wasAcquiredAfterRelease = await acquired.get()
        XCTAssertTrue(wasAcquiredAfterRelease)
    }

    func testUnavailableStorageFailsClosedBeforeWritingAsset() async throws {
        let store = ShowAssetMediaStore(storageError: .storageUnavailable)
        do {
            _ = try await store.saveImage(
                data: try XCTUnwrap(solidJPEGData()),
                showID: UUID(),
                kind: .ticket
            )
            XCTFail("Unavailable storage must reject the asset before writing")
        } catch {
            XCTAssertEqual(error as? ShowAssetMediaStoreError, .storageUnavailable)
        }
    }

    func testUniqueKeyIsStablePerShowAndKind() {
        let showID = UUID()
        XCTAssertEqual(
            ShowAsset.makeUniqueKey(showID: showID, kind: .ticket),
            "\(showID.uuidString)|ticket"
        )
        XCTAssertNotEqual(
            ShowAsset.makeUniqueKey(showID: showID, kind: .ticket),
            ShowAsset.makeUniqueKey(showID: showID, kind: .timetable)
        )
    }

    func testAssetPathMustStayUnderItsShowAndKindDirectory() {
        let showID = UUID()
        XCTAssertTrue(
            ShowAsset.isValidRelativePath(
                "\(showID.uuidString)/ticket/image.jpg",
                showID: showID,
                kind: .ticket
            )
        )
        XCTAssertFalse(
            ShowAsset.isValidRelativePath(
                "\(showID.uuidString)/timetable/image.jpg",
                showID: showID,
                kind: .ticket
            )
        )
        XCTAssertFalse(
            ShowAsset.isValidRelativePath(
                "\(showID.uuidString)/ticket/../other.jpg",
                showID: showID,
                kind: .ticket
            )
        )
    }

    func testPrivacyCopyMentionsLocalTicketAssetsWithoutTicketWalletLanguage() {
        let joined = PrivacyLocalDataCopy.points.joined(separator: " ")
        XCTAssertTrue(joined.contains("票根"))
        XCTAssertTrue(joined.contains("时刻表"))
        XCTAssertTrue(joined.contains("本机") || joined.contains("本地"))
        XCTAssertFalse(joined.contains("验票"))
        XCTAssertFalse(joined.contains("票夹"))
        XCTAssertTrue(PrivacyLocalDataCopy.clearDataExplanation.contains("票根"))
        XCTAssertTrue(
            LocalDataClearancePolicy.defaultPlan.deletesAppOwnedData.contains {
                $0.contains("票根") && $0.contains("时刻表")
            }
        )
    }

    private func solidJPEGData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}

private actor BooleanBox {
    private var value = false

    func setTrue() {
        value = true
    }

    func get() -> Bool {
        value
    }
}
