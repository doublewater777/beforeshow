import XCTest
@testable import BeforeShow

@MainActor
final class FootprintDetailPresentationTests: XCTestCase {
    func testMemoryOpensInTheMatchingSurfaceWithItsInitialMediaIndex() throws {
        let presentation = FootprintDetailPresentation()
        let fragment = try MemoryFragment(showID: UUID(), text: "散场后的记忆")

        presentation.openMemory(fragment)
        guard case .textMemory(let text, let textIndex) = presentation.sheet else {
            return XCTFail("Text memories must open in a sheet")
        }
        XCTAssertEqual(text.id, fragment.id)
        XCTAssertEqual(textIndex, 0)
        XCTAssertNil(presentation.fullScreenCover)

        try fragment.appendMedia(MemoryMediaItem(
            id: UUID(), kind: .photo, relativePath: "photo.jpg",
            thumbnailRelativePath: nil, contentTypeIdentifier: "public.jpeg",
            videoDuration: nil, sortOrder: 0
        ))
        try fragment.appendMedia(MemoryMediaItem(
            id: UUID(), kind: .video, relativePath: "video.mov",
            thumbnailRelativePath: "video.jpg", contentTypeIdentifier: "com.apple.quicktime-movie",
            videoDuration: 3, sortOrder: 1
        ))
        presentation.openMemory(fragment, initialIndex: 1)
        guard case .mediaMemory(let media, let mediaIndex) = presentation.fullScreenCover else {
            return XCTFail("Media memories must open full screen")
        }
        XCTAssertEqual(media.id, fragment.id)
        XCTAssertEqual(mediaIndex, 1)
        XCTAssertNil(presentation.sheet)
    }

    func testInactiveSurfaceDismissalDoesNotCloseTheCurrentDestination() {
        let presentation = FootprintDetailPresentation()
        presentation.present(.asset(.ticket))
        XCTAssertNotNil(presentation.sheet)

        presentation.openShare(.composer)
        presentation.sheet = nil
        presentation.isShowingDeleteConfirmation = false
        XCTAssertNil(presentation.sheet)
        XCTAssertEqual(presentation.fullScreenCover?.id, FootprintDetailOverlay.shareComposer.id)

        presentation.present(.editor)
        presentation.fullScreenCover = nil
        XCTAssertEqual(presentation.sheet?.id, FootprintDetailOverlay.editor.id)

        presentation.present(.deleteConfirmation)
        presentation.sheet = nil
        XCTAssertTrue(presentation.isShowingDeleteConfirmation)
        XCTAssertNil(presentation.sheet)
        XCTAssertNil(presentation.fullScreenCover)
        presentation.isShowingDeleteConfirmation = false
        XCTAssertNil(presentation.destination)
    }

    func testShareFallbackAndDismissalUseOneDestination() {
        let presentation = FootprintDetailPresentation()
        presentation.openShare(.none)
        XCTAssertNil(presentation.destination)

        presentation.openShare(.dispersalCard)
        XCTAssertEqual(presentation.sheet?.id, FootprintDetailOverlay.dispersalShare.id)
        XCTAssertNil(presentation.fullScreenCover)
        presentation.sheet = nil
        XCTAssertNil(presentation.destination)

        presentation.openShare(.composer)
        presentation.fullScreenCover = nil
        XCTAssertNil(presentation.destination)

        presentation.present(.ceremonyEditor)
        presentation.dismiss()
        XCTAssertNil(presentation.destination)
    }

    func testPlaybackStopsForEveryPresentationAndResumesOnlyInTheForeground() throws {
        let presentation = FootprintDetailPresentation()
        let fragment = try MemoryFragment(showID: UUID(), text: "记忆")
        let destinations: [FootprintDetailOverlay] = [
            .textMemory(fragment, initialIndex: 0), .mediaMemory(fragment, initialIndex: 0),
            .asset(.ticket), .asset(.timetable), .memoryPage, .editor,
            .shareComposer, .dispersalShare, .ceremonyEditor, .deleteConfirmation
        ]
        XCTAssertTrue(presentation.isPlaybackActive(sceneIsActive: true))
        XCTAssertFalse(presentation.isPlaybackActive(sceneIsActive: false))

        for destination in destinations {
            presentation.present(destination)
            XCTAssertFalse(presentation.isPlaybackActive(sceneIsActive: true), destination.id)
            presentation.dismiss()
            XCTAssertTrue(presentation.isPlaybackActive(sceneIsActive: true), destination.id)
            XCTAssertFalse(presentation.isPlaybackActive(sceneIsActive: false), destination.id)
        }
    }
}
