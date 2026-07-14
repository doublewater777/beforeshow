import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ShowFragmentSessionTests: XCTestCase {
    func testCanSaveRequiresTextMediaOrAudio() throws {
        let show = try Show(name: "碎片", date: Date(), startTime: Date(), type: .concert)
        let session = ShowFragmentSession(show: show)

        XCTAssertFalse(session.canSave(text: "  ", galleryReferenceCount: 0, hasAudio: false))
        XCTAssertTrue(session.canSave(text: "一句", galleryReferenceCount: 0, hasAudio: false))
        XCTAssertTrue(session.canSave(text: "", galleryReferenceCount: 1, hasAudio: false))
        XCTAssertTrue(session.canSave(text: "", galleryReferenceCount: 0, hasAudio: true))
    }

    func testCreatePersistsGalleryAndAudioAttachments() throws {
        let show = try Show(name: "碎片现场", date: Date(), startTime: Date(), type: .concert)
        let container = try ModelContainer(
            for: Show.self, ShowFragment.self, ShowFragmentGalleryMediaReference.self, ShowFragmentAudioReference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(show)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = ShowFragmentSession(
            show: show,
            deletionService: LocalAppDataDeletionService(
                audioStorage: ShowFragmentAudioStorage(rootDirectory: root)
            )
        )

        let fragment = try session.create(
            text: "  排队中  ",
            galleryReferences: [
                (localIdentifier: "asset-1", kind: .photo),
                (localIdentifier: "asset-2", kind: .video)
            ],
            audioRelativePath: "FragmentAudio/clip.m4a",
            audioDuration: 3.5,
            in: context
        )

        XCTAssertEqual(fragment.text, "排队中")
        XCTAssertEqual(fragment.galleryMediaReferences.count, 2)
        XCTAssertEqual(fragment.audioReference?.relativePath, "FragmentAudio/clip.m4a")
        XCTAssertEqual(fragment.audioReference?.duration, 3.5)

        let fetched = try context.fetch(FetchDescriptor<ShowFragment>())
        XCTAssertEqual(fetched.count, 1)
    }

    func testDeleteRemovesFragmentThroughSession() throws {
        let show = try Show(name: "碎片现场", date: Date(), startTime: Date(), type: .concert)
        let container = try ModelContainer(
            for: Show.self, ShowFragment.self, ShowFragmentGalleryMediaReference.self, ShowFragmentAudioReference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(show)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = ShowFragmentSession(
            show: show,
            deletionService: LocalAppDataDeletionService(
                audioStorage: ShowFragmentAudioStorage(rootDirectory: root)
            )
        )

        let fragment = try session.create(
            text: "要删",
            galleryReferences: [],
            audioRelativePath: nil,
            audioDuration: nil,
            in: context
        )
        try session.delete(fragment, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShowFragment>()).isEmpty)
    }
}
