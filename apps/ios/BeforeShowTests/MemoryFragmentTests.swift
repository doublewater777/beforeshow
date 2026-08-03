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
        fragment.appendMedia(makeMedia(kind: .video, order: 9))
        fragment.appendMedia(makeMedia(kind: .photo, order: 9))

        XCTAssertEqual(fragment.orderedMediaItems.map(\.kind), [.video, .photo])
        XCTAssertEqual(fragment.orderedMediaItems.map(\.sortOrder), [0, 1])
    }

    func testRemovingLastMediaRequiresText() throws {
        let withoutText = try MemoryFragment(showID: UUID())
        let onlyMedia = makeMedia(kind: .photo, order: 0)
        withoutText.appendMedia(onlyMedia)

        XCTAssertThrowsError(try withoutText.removeMedia(onlyMedia)) {
            XCTAssertEqual($0 as? MemoryFragmentValidationError, .emptyContent)
        }
        XCTAssertEqual(withoutText.mediaItems.count, 1)

        let withText = try MemoryFragment(showID: UUID(), text: "保留文字")
        let removable = makeMedia(kind: .video, order: 0)
        withText.appendMedia(removable)
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
        fragment.appendMedia(makeMedia(kind: .photo, order: 0))
        try fragment.updateText(nil)
        XCTAssertNil(fragment.text)
        XCTAssertEqual(fragment.mediaItems.count, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: MemoryFragment.self,
            MemoryMediaItem.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
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
