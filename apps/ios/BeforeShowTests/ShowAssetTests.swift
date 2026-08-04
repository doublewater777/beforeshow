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
        XCTAssertTrue(relativePath.contains(showID.uuidString))
        XCTAssertTrue(relativePath.contains(ShowAssetKind.ticket.directoryName))

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

        let linked = ShowAsset(
            showID: show.id,
            kind: .ticket,
            relativePath: "\(show.id.uuidString)/ticket/a.jpg"
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

        let valid = try reconcileShowAssetShowBoundary(in: context)
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

    private func solidJPEGData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
