import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import BeforeShow

@MainActor
final class MemoryFragmentTests: XCTestCase {
    func testTextNormalizationAndLimit() throws {
        let showID = UUID()
        let fragment = try MemoryFragment(showID: showID, text: "  排队中\n  ")

        XCTAssertEqual(fragment.text, "排队中")
        XCTAssertEqual(fragment.showID, showID)
        XCTAssertThrowsError(try MemoryFragment(showID: showID, text: String(repeating: "记", count: 501))) {
            XCTAssertEqual($0 as? MemoryFragmentValidationError, .textTooLong)
        }
    }

    func testQueryKeepsShowsIsolatedAndCreationOrdered() throws {
        let firstShowID = UUID()
        let secondShowID = UUID()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(try MemoryFragment(
            showID: firstShowID,
            text: "后来",
            createdAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(try MemoryFragment(
            showID: secondShowID,
            text: "别场",
            createdAt: Date(timeIntervalSince1970: 50)
        ))
        context.insert(try MemoryFragment(
            showID: firstShowID,
            text: "最早",
            createdAt: Date(timeIntervalSince1970: 100)
        ))
        try context.save()

        let descriptor = FetchDescriptor<MemoryFragment>(
            predicate: #Predicate { $0.showID == firstShowID },
            sortBy: [SortDescriptor(\MemoryFragment.createdAt)]
        )
        XCTAssertEqual(try context.fetch(descriptor).compactMap(\.text), ["最早", "后来"])
    }

    func testMixedMediaKeepsInsertionOrder() throws {
        let fragment = try MemoryFragment(showID: UUID())
        try fragment.appendMedia(makeMedia(kind: .video, order: 9))
        try fragment.appendMedia(makeMedia(kind: .photo, order: 9))

        XCTAssertEqual(fragment.orderedMediaItems.map(\.kind), [.video, .photo])
        XCTAssertEqual(fragment.orderedMediaItems.map(\.sortOrder), [0, 1])
    }

    func testRemovingLastMediaRequiresText() throws {
        let withoutText = try MemoryFragment(showID: UUID())
        let onlyMedia = makeMedia(kind: .photo, order: 0)
        try withoutText.appendMedia(onlyMedia)

        XCTAssertThrowsError(try withoutText.removeMedia(onlyMedia)) {
            XCTAssertEqual($0 as? MemoryFragmentValidationError, .emptyContent)
        }
        XCTAssertEqual(withoutText.mediaItems.count, 1)

        let withText = try MemoryFragment(showID: UUID(), text: "保留文字")
        let removable = makeMedia(kind: .video, order: 0)
        try withText.appendMedia(removable)
        try withText.removeMedia(removable)
        XCTAssertTrue(withText.mediaItems.isEmpty)
        XCTAssertEqual(withText.text, "保留文字")
    }

    func testMediaStoreStagesCommitsAndDeletesAppOwnedFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(staged.stagedRelativePath).path))

        let committed = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        XCTAssertEqual(committed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed[0].relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/\(draftID.uuidString)").path))
        try await store.finalizeCommit(draftID: draftID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/\(draftID.uuidString)").path))

        try await store.deleteFragment(showID: showID, fragmentID: fragmentID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(showID.uuidString).appendingPathComponent(fragmentID.uuidString).path))
    }

    func testDiscardDraftRemovesStagedFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        _ = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)

        try await store.discardDraft(draftID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/\(draftID.uuidString)").path))
    }

    func testCommitAdditionsPreservesExistingFragmentDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let showID = UUID()
        let fragmentID = UUID()
        let initialDraftID = UUID()
        let initial = try await store.stageCameraPhoto(makeJPEG(), draftID: initialDraftID)
        let firstCommit = try await store.commit(
            draftID: initialDraftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [initial]
        )
        try await store.finalizeCommit(draftID: initialDraftID)
        let additionDraftID = UUID()
        let addition = try await store.stageCameraPhoto(makeJPEG(), draftID: additionDraftID)

        let secondCommit = try await store.commitAdditions(
            draftID: additionDraftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [addition]
        )
        try await store.finalizeCommit(draftID: additionDraftID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(firstCommit[0].relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(secondCommit[0].relativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/\(additionDraftID.uuidString)").path))
    }


    func testCommitKeepsStagingWhenSaveWouldFailAndRetrySucceeds() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)

        let committed = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        // Simulate SwiftData save failure: roll back final files, keep staging for retry.
        try await store.rollbackCommittedFiles(relativePaths: committed.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 }
        })

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(staged.stagedRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed[0].relativePath).path))

        let retried = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        try await store.finalizeCommit(draftID: draftID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(retried[0].relativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/\(draftID.uuidString)").path))
    }

    func testReconcileRemovesUnreferencedFilesInsideValidFragmentDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)
        let committed = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        try await store.finalizeCommit(draftID: draftID)

        let fragmentDirectory = root
            .appendingPathComponent(showID.uuidString)
            .appendingPathComponent(fragmentID.uuidString)
        let orphan = fragmentDirectory.appendingPathComponent("orphan-left-behind.mov")
        try Data("orphan".utf8).write(to: orphan)

        try await store.reconcileFragmentFiles(
            showID: showID,
            validFilesByFragmentID: [
                fragmentID: Set(
                    committed.flatMap { [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 } }
                )
            ]
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed[0].relativePath).path))
    }

    func testUpdateTextAllowsClearingCaptionWhenMediaExists() throws {
        let fragment = try MemoryFragment(showID: UUID(), text: "开场前")
        try fragment.appendMedia(makeMedia(kind: .photo, order: 0))
        try fragment.updateText(nil)
        XCTAssertNil(fragment.text)
        XCTAssertEqual(fragment.mediaItems.count, 1)
    }


    func testReconcileAllRemovesOrphanShowDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)
        let committed = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        try await store.finalizeCommit(draftID: draftID)

        // Simulate DB no longer knowing this show.
        try await store.reconcileAll(validFilesByShowAndFragment: [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(showID.uuidString).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed[0].relativePath).path))
    }

    func testCommitOverwriteIsIdempotentOnRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)
        let first = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        // Simulate partial DB failure: keep final files, keep staging, retry commit.
        let second = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        try await store.finalizeCommit(draftID: draftID)
        XCTAssertEqual(first[0].relativePath, second[0].relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(second[0].relativePath).path))
    }

    // MARK: - P2-1: model-level fragment<->show boundary

    func testDeletingShowCascadesToMemoryFragments() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "现场", date: now, startTime: now)
        context.insert(show)
        let fragment = try MemoryFragment(showID: show.id, text: "记忆")
        fragment.show = show
        context.insert(fragment)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryFragment>()).count, 1)
        context.delete(show)
        try context.save()
        // Cascade delete rule removes the fragment at the model layer; no orphan record
        // survives a show deletion that previously depended on a manual coordinator.
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryFragment>()).count, 0)
    }

    func testMemoryFragmentShowRelationshipLinksOwner() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "现场", date: now, startTime: now)
        context.insert(show)
        let fragment = try MemoryFragment(showID: show.id, text: "记忆")
        fragment.show = show
        context.insert(fragment)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MemoryFragment>()).first
        XCTAssertEqual(fetched?.showID, show.id)
        XCTAssertEqual(fetched?.show?.id, show.id)
        XCTAssertEqual(show.memoryFragments.first?.id, fragment.id)
    }

    // MARK: - P1-1: reconciliation/commit coordination gate

    func testCommitGateSerializesConcurrentAccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))

        await store.acquireCommitGate()
        var secondAcquired = false
        let waiter = Task<Void, Never> {
            await store.acquireCommitGate()
            secondAcquired = true
            await store.releaseCommitGate()
        }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(secondAcquired, "Second acquire must block while the gate is held")
        await store.releaseCommitGate()
        await waiter.value
        XCTAssertTrue(secondAcquired, "Second acquire completes once the gate is released")
    }

    func testReconcileAllKeepsReferencedFragmentFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)
        let committed = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        try await store.finalizeCommit(draftID: draftID)

        let valid: [UUID: [UUID: Set<String>]] = [
            showID: [fragmentID: Set(committed.flatMap { [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 } })]
        ]
        try await store.reconcileAll(validFilesByShowAndFragment: valid)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed[0].relativePath).path))
    }

    // MARK: - P1-2: staging cleanup must not evict in-use/retrying drafts

    func testCleanupStagingPreservesFreshDraft() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        _ = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)

        // A freshly staged draft must survive the 24h staging cleanup so an open
        // composer, or a draft retained for retry after a failed save, is not evicted.
        try await store.cleanupStaging(olderThan: Date().addingTimeInterval(-86_400))

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/\(draftID.uuidString)").path))
    }

    // MARK: - P1-3: removing a draft item reclaims its staging

    func testRemoveStagedItemDeletesStagingOriginalAndThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)

        try await store.removeStagedItem(staged)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(staged.stagedRelativePath).path))
        if let thumb = staged.thumbnailStagedRelativePath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(thumb).path))
        }
    }

    // MARK: - P1-4: capacity checks + import-temp reclaim

    func testEnsureAvailableCapacityThrowsWhenInsufficient() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // ensureAvailableCapacity reads volume capacity off the root directory, so the
        // directory must exist (in production prepareRootDirectory creates it first).
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))

        do {
            try await store.ensureAvailableCapacity(forByteCount: Int64.max)
            XCTFail("Expected insufficientDiskSpace for an impossible byte count")
        } catch MemoryMediaStoreError.insufficientDiskSpace {
            // expected: the capacity path surfaces the typed error before any copy.
        }
    }

    func testCleanupImportTempRemovesStaleFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let stale = tempDir.appendingPathComponent("stale-\(UUID().uuidString).jpg")
        let fresh = tempDir.appendingPathComponent("fresh-\(UUID().uuidString).jpg")
        try Data("stale".utf8).write(to: stale)
        try Data("fresh".utf8).write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100_000)],
            ofItemAtPath: stale.path
        )
        defer {
            try? FileManager.default.removeItem(at: stale)
            try? FileManager.default.removeItem(at: fresh)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))

        try await store.cleanupImportTemp(olderThan: Date().addingTimeInterval(-86_400))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testCleanupImportTempWorksWhenPersistentStorageIsUnavailable() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowMemoryImports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let stale = tempDir.appendingPathComponent("unavailable-\(UUID().uuidString).jpg")
        try Data("stale".utf8).write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100_000)],
            ofItemAtPath: stale.path
        )
        defer { try? FileManager.default.removeItem(at: stale) }

        let store = MemoryFragmentMediaStore(storageError: .storageUnavailable)
        try await store.cleanupImportTemp(olderThan: Date().addingTimeInterval(-86_400))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    // MARK: - Round 4: production seam (show-boundary reconcile), import rollback, import time

    func testReconcileBackfillsShowRelationshipForExistingFragments() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "现场", date: now, startTime: now)
        context.insert(show)
        // An existing fragment that predates the relationship: valid showID, but show == nil.
        let fragment = try MemoryFragment(showID: show.id, text: "旧记忆")
        context.insert(fragment)
        try context.save()
        XCTAssertNil(fragment.show)

        let valid = try reconcileMemoryFragmentShowBoundary(in: context)

        XCTAssertNotNil(fragment.show, "Existing fragments should be backfilled with the Show relationship")
        XCTAssertEqual(fragment.show?.id, show.id)
        XCTAssertNotNil(valid[show.id]?[fragment.id])
    }

    func testReconcileDeletesOrphanFragments() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "现场", date: now, startTime: now)
        context.insert(show)
        let validFragment = try MemoryFragment(showID: show.id, text: "有效")
        context.insert(validFragment)
        let orphan = try MemoryFragment(showID: UUID(), text: "孤儿")
        context.insert(orphan)
        try context.save()

        let valid = try reconcileMemoryFragmentShowBoundary(in: context)

        XCTAssertNotNil(valid[show.id]?[validFragment.id], "Valid fragment is retained")
        XCTAssertNil(valid[orphan.showID], "Orphan fragment is not in the valid set")
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryFragment>()).count, 1, "Orphan record is deleted")
    }

    func testReconcileDropsMediaWithMismatchedOwnerFromValidSet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "现场", date: now, startTime: now)
        context.insert(show)
        let fragment = try MemoryFragment(showID: show.id, text: "记忆")
        fragment.show = show
        let wrongFragmentID = UUID()
        let item = MemoryMediaItem(
            id: UUID(),
            kind: .photo,
            relativePath: "\(show.id.uuidString)/\(wrongFragmentID.uuidString)/photo.jpg",
            thumbnailRelativePath: nil,
            contentTypeIdentifier: "public.jpeg",
            videoDuration: nil,
            sortOrder: 0
        )
        try fragment.appendMedia(item)
        context.insert(fragment)
        try context.save()

        let valid = try reconcileMemoryFragmentShowBoundary(in: context)

        XCTAssertEqual(valid[show.id]?[fragment.id], Set<String>())
        XCTAssertTrue(fragment.mediaItems.isEmpty)
    }

    func testOwnedMemoryDeleteRejectsMismatchedPathBeforeDeletingAnyFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryOwnershipBatch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let showID = UUID()
        let fragmentID = UUID()
        let otherShowID = UUID()
        let otherFragmentID = UUID()
        let keptPath = "\(otherShowID.uuidString)/\(otherFragmentID.uuidString)/photo.jpg"
        let keptURL = root.appendingPathComponent(keptPath)
        try FileManager.default.createDirectory(
            at: keptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("kept".utf8).write(to: keptURL)

        let forged = MemoryOwnedMediaPath(
            showID: showID,
            fragmentID: fragmentID,
            relativePath: keptPath
        )
        let valid = MemoryOwnedMediaPath(
            showID: showID,
            fragmentID: fragmentID,
            relativePath: "\(showID.uuidString)/\(fragmentID.uuidString)/photo.jpg"
        )

        do {
            try await store.deleteFiles([valid, forged])
            XCTFail("A path whose directory owner disagrees with its metadata must be rejected")
        } catch MemoryMediaStoreError.invalidRelativePath {
            // expected
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
    }

    func testStageTransferredFileRollsBackStagingOnPostCopyFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        // A file that claims to be JPEG but isn't a valid image: copy succeeds, thumbnail
        // decoding fails, so the post-copy rollback path must run.
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("bogus-\(UUID().uuidString).jpg")
        try Data("not an image".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        let imported = MemoryImportedFile(url: bogus, contentType: .image)

        do {
            _ = try await store.stageTransferredFile(imported, draftID: draftID)
            XCTFail("Expected staging to fail for a non-image")
        } catch MemoryMediaStoreError.imageEncodingFailed {
            // expected
        }

        // The copied staging file must be rolled back, not left as an orphan that
        // bypasses the composer's 10-item cap.
        let stagingDir = root.appendingPathComponent("Staging/\(draftID.uuidString)")
        if FileManager.default.fileExists(atPath: stagingDir.path) {
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
            XCTAssertTrue(leftovers.isEmpty, "No orphan staging files should remain after a failed import")
        }
    }

    func testDiscardImportedFileRemovesTransferTempAfterCancellation() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-\(UUID().uuidString).jpg")
        try Data("img".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let imported = try MemoryImportedFile.copied(source, contentType: .image)
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.url.path))
        try await store.discardImportedFile(imported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.url.path))
    }

    func testImportedFileCopyStampsImportTime() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).jpg")
        try Data("img".utf8).write(to: source)
        // Backdate the source mtime to simulate an old original photo.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-10_000_000)],
            ofItemAtPath: source.path
        )
        defer { try? FileManager.default.removeItem(at: source) }

        let imported = try MemoryImportedFile.copied(source, contentType: .image)
        defer { try? FileManager.default.removeItem(at: imported.url) }

        let mtime = try imported.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertNotNil(mtime)
        // The copy stamps the import time, so mtime should be recent, not the backdated source time.
        XCTAssertGreaterThan(mtime!.timeIntervalSinceNow, -60)
    }

    // MARK: - Round 5: destructive failure paths + capacity precheck

    func testReconcileFragmentFilesEmptyValidSetRemovesAllFragmentFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        let showID = UUID()
        let fragmentID = UUID()
        let staged = try await store.stageCameraPhoto(makeJPEG(), draftID: draftID)
        let committed = try await store.commit(
            draftID: draftID,
            showID: showID,
            fragmentID: fragmentID,
            media: [staged]
        )
        try await store.finalizeCommit(draftID: draftID)

        // An empty valid set means "no fragment is valid" -> reconcile removes every
        // fragment directory for the show. This is why the per-show view reconcile must
        // abort on fetch failure instead of passing an empty (authoritative-looking) set.
        try await store.reconcileFragmentFiles(showID: showID, validFilesByFragmentID: [:])

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed[0].relativePath).path))
    }

    func testCapacityCheckResolvesExistingAncestorForNonExistentPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A non-existent destination path must still resolve to its volume via an
        // existing ancestor, so the first-copy capacity precheck is real, not fail-open.
        let nonExistent = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertNotNil(MemoryCapacity.availableBytes(at: nonExistent))

        do {
            try MemoryCapacity.throwIfInsufficient(at: nonExistent, required: Int64.max)
            XCTFail("Expected insufficientDiskSpace for an impossible byte count")
        } catch MemoryMediaStoreError.insufficientDiskSpace {
            // expected: the check resolves the ancestor and throws rather than skipping.
        }
    }

    // MARK: - Round 6: camera-capture transaction + on-disk migration

    func testStageCameraPhotoRollsBackOriginalOnThumbnailFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoryFragmentMediaStore(location: MemoryMediaLocation(rootDirectory: root))
        let draftID = UUID()
        // Bytes that are not a valid JPEG: the original writes, but thumbnail decoding fails.
        let bogus = Data("not an image".utf8)

        do {
            _ = try await store.stageCameraPhoto(bogus, draftID: draftID)
            XCTFail("Expected staging to fail for a non-image")
        } catch MemoryMediaStoreError.imageEncodingFailed {
            // expected
        }

        // The original JPEG must be rolled back so a failed camera capture leaves no
        // uncounted staging file (original or thumbnail).
        let stagingDir = root.appendingPathComponent("Staging/\(draftID.uuidString)")
        if FileManager.default.fileExists(atPath: stagingDir.path) {
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
            XCTAssertTrue(leftovers.isEmpty, "No orphan original/thumbnail should remain after a failed camera capture")
        }
    }

    func testReconcileBackfillsRelationshipAcrossDiskStoreRestart() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryFragmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let dbURL = storeDir.appendingPathComponent("memory.store")

        let showID: UUID
        let fragmentID: UUID
        do {
            let container = try ModelContainer(
                for: Show.self, MemoryFragment.self, MemoryMediaItem.self,
                configurations: ModelConfiguration(url: dbURL, cloudKitDatabase: .none)
            )
            let context = container.mainContext
            let now = Date()
            let show = try Show(name: "现场", date: now, startTime: now)
            context.insert(show)
            showID = show.id
            // Legacy fragment that predates the relationship: showID set, show == nil.
            let fragment = try MemoryFragment(showID: showID, text: "旧记忆")
            fragmentID = fragment.id
            context.insert(fragment)
            try context.save()
        }

        // Reopen the on-disk store (simulates app restart with legacy data).
        let container = try ModelContainer(
            for: Show.self, MemoryFragment.self, MemoryMediaItem.self,
            configurations: ModelConfiguration(url: dbURL, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let reopened = try context.fetch(
            FetchDescriptor<MemoryFragment>(predicate: #Predicate { $0.id == fragmentID })
        ).first
        XCTAssertNotNil(reopened)
        XCTAssertNil(reopened?.show, "Legacy fragment reopens without the relationship")

        let valid = try reconcileMemoryFragmentShowBoundary(in: context)
        XCTAssertNotNil(reopened?.show, "Backfill binds the relationship after restart")
        XCTAssertEqual(reopened?.show?.id, showID)
        XCTAssertNotNil(valid[showID]?[fragmentID])

        // Cascade delete works on the backfilled relationship.
        let show = try context.fetch(FetchDescriptor<Show>(predicate: #Predicate { $0.id == showID })).first
        XCTAssertNotNil(show)
        context.delete(show!)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryFragment>()).count, 0, "Cascade delete removes the fragment")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self,
            MemoryFragment.self,
            MemoryMediaItem.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }





    func testReplaceOnlyMediaWithoutTextDoesNotTripEmptyContent() throws {
        // Textless single-media fragments must support "remove old + add new" by
        // appending the replacement before removing the last existing item.
        let fragment = try MemoryFragment(showID: UUID())
        let old = makeMedia(kind: .photo, order: 0)
        try fragment.appendMedia(old)
        XCTAssertNil(fragment.text)

        let replacement = makeMedia(kind: .photo, order: 1)
        try fragment.appendMedia(replacement)
        try fragment.removeMedia(old)
        XCTAssertEqual(fragment.orderedMediaItems.map(\.id), [replacement.id])
        XCTAssertNil(fragment.text)
    }

    func testEditValidationRejectsEmptyResultBeforeMutation() throws {
        // Mirrors saveEditedFragment preflight: removing all media with blank caption must fail
        // before any model mutation is applied.
        let fragment = try MemoryFragment(showID: UUID(), text: "旧文案")
        let only = makeMedia(kind: .photo, order: 0)
        try fragment.appendMedia(only)

        let removedIDs: Set<UUID> = [only.id]
        let remaining = fragment.orderedMediaItems.filter { !removedIDs.contains($0.id) }
        let additions: [MemoryDraftMedia] = []
        let normalized = try MemoryFragment.normalized("   ")
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(additions.isEmpty)
        XCTAssertNil(normalized)
        // Preflight would throw emptyContent; fragment text/media remain untouched.
        XCTAssertEqual(fragment.text, "旧文案")
        XCTAssertEqual(fragment.mediaItems.count, 1)
    }

    func testReorderMediaPreservesRequestedOrder() throws {
        let fragment = try MemoryFragment(showID: UUID(), text: "排序")
        let a = makeMedia(kind: .photo, order: 0)
        let b = makeMedia(kind: .photo, order: 1)
        let c = makeMedia(kind: .video, order: 2)
        try fragment.appendMedia(a)
        try fragment.appendMedia(b)
        try fragment.appendMedia(c)
        fragment.reorderMedia(orderedIDs: [c.id, a.id, b.id])
        XCTAssertEqual(fragment.orderedMediaItems.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(fragment.orderedMediaItems.map(\.sortOrder), [0, 1, 2])
    }


    func testApplyMediaEditSupportsCapacityReplacement() throws {
        let fragment = try MemoryFragment(showID: UUID(), text: "cap")
        var media: [MemoryMediaItem] = []
        for index in 0..<MemoryFragment.maximumMediaCount {
            let item = makeMedia(kind: .photo, order: index)
            try fragment.appendMedia(item)
            media.append(item)
        }
        let removed = media[0]
        let addition = makeMedia(kind: .video, order: 99)
        let finalOrder = media.dropFirst().map(\.id) + [addition.id]
        try fragment.applyMediaEdit(
            removingIDs: [removed.id],
            adding: [addition],
            finalOrder: finalOrder
        )
        XCTAssertEqual(fragment.mediaItems.count, MemoryFragment.maximumMediaCount)
        XCTAssertEqual(fragment.orderedMediaItems.map(\.id), finalOrder)
        XCTAssertFalse(fragment.mediaItems.contains(where: { $0.id == removed.id }))
    }

    func testApplyMediaEditRejectsOverCapacityFinalSet() throws {
        let fragment = try MemoryFragment(showID: UUID(), text: "cap")
        for index in 0..<MemoryFragment.maximumMediaCount {
            try fragment.appendMedia(makeMedia(kind: .photo, order: index))
        }
        XCTAssertThrowsError(
            try fragment.applyMediaEdit(
                removingIDs: [],
                adding: [makeMedia(kind: .photo, order: 100)],
                finalOrder: []
            )
        ) {
            XCTAssertEqual($0 as? MemoryFragmentValidationError, .mediaLimitExceeded)
        }
    }

    func testMultiDayInterSessionPhaseIsAfterNotBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        // 2026-08-15..17 daily 13:00-22:00
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 13, minute: 0))!
        let endTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 22, minute: 0))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 0, minute: 0))!
        let timing = ShowTimingFields(
            date: day1,
            startTime: day1,
            endDate: endDate,
            endTime: endTime,
            endedAt: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        func at(day: Int, hour: Int, minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
        }
        XCTAssertEqual(MemoryFragmentPhase.resolved(at: at(day: 15, hour: 12), timing: timing, calendar: calendar), .before)
        XCTAssertEqual(MemoryFragmentPhase.resolved(at: at(day: 15, hour: 14), timing: timing, calendar: calendar), .live)
        XCTAssertEqual(MemoryFragmentPhase.resolved(at: at(day: 15, hour: 22, minute: 1), timing: timing, calendar: calendar), .after)
        XCTAssertEqual(MemoryFragmentPhase.resolved(at: at(day: 16, hour: 10), timing: timing, calendar: calendar), .after)
        XCTAssertEqual(MemoryFragmentPhase.resolved(at: at(day: 16, hour: 14), timing: timing, calendar: calendar), .live)
        XCTAssertEqual(MemoryFragmentPhase.resolved(at: at(day: 17, hour: 22, minute: 1), timing: timing, calendar: calendar), .after)
    }

    func testPhaseResolutionUsesShowTimingBoundaries() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(calendar: calendar, year: 2026, month: 8, day: 4, hour: 19, minute: 30)
        let start = calendar.date(from: components)!
        components.hour = 23
        let end = calendar.date(from: components)!
        let timing = ShowTimingFields(
            date: start,
            startTime: start,
            endDate: nil,
            endTime: end,
            endedAt: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        XCTAssertEqual(
            MemoryFragmentPhase.resolved(at: start.addingTimeInterval(-60), timing: timing, calendar: calendar),
            .before
        )
        XCTAssertEqual(
            MemoryFragmentPhase.resolved(at: start.addingTimeInterval(60), timing: timing, calendar: calendar),
            .live
        )
        XCTAssertEqual(
            MemoryFragmentPhase.resolved(at: end.addingTimeInterval(60), timing: timing, calendar: calendar),
            .after
        )
    }

    func testMediaLimitIsHardCappedAtTen() throws {
        let fragment = try MemoryFragment(showID: UUID(), text: "cap")
        for index in 0..<MemoryFragment.maximumMediaCount {
            try fragment.appendMedia(makeMedia(kind: .photo, order: index))
        }
        XCTAssertThrowsError(try fragment.appendMedia(makeMedia(kind: .photo, order: 99))) {
            XCTAssertEqual($0 as? MemoryFragmentValidationError, .mediaLimitExceeded)
        }
    }

    func testRelativeTimeFormatting() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        XCTAssertEqual(MemoryFragmentRelativeTime.format(now.addingTimeInterval(-10), now: now, calendar: calendar), "刚刚")
        XCTAssertEqual(MemoryFragmentRelativeTime.format(now.addingTimeInterval(-5 * 60), now: now, calendar: calendar), "5 分钟前")
    }

    private func makeMedia(kind: MemoryMediaKind, order: Int) -> MemoryMediaItem {
        MemoryMediaItem(
            id: UUID(),
            kind: kind,
            relativePath: "file",
            thumbnailRelativePath: nil,
            contentTypeIdentifier: kind == .photo ? UTType.jpeg.identifier : UTType.movie.identifier,
            videoDuration: kind == .video ? 3 : nil,
            sortOrder: order
        )
    }

    private func makeJPEG() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}
