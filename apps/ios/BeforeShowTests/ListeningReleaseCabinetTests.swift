import XCTest
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningReleaseCabinetTests: XCTestCase {
    func testArtistCabinetIncludesEPAndSingleReleases() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
                .first { $0.artistID == "a" }
        )

        context.insert(CatalogAlbum(
            appleMusicAlbumID: "fixture-ep",
            title: "Fixture EP",
            artistIDs: ["a"],
            isSingle: false,
            orderedTrackIDs: ["a1", "a2"]
        ))
        context.insert(CatalogAlbum(
            appleMusicAlbumID: "fixture-single",
            title: "Fixture Single",
            artistIDs: ["a"],
            isSingle: true,
            orderedTrackIDs: ["a1"]
        ))
        snapshot.albumIDs.append(contentsOf: ["fixture-ep", "fixture-single"])
        try context.save()

        let room = ListenTestData.room(context)
        await room.load(show: show)
        room.selectScope(.artist("a"))

        XCTAssertTrue(room.libraryDiscs.contains { $0.id == "fixture-ep" })
        XCTAssertTrue(room.libraryDiscs.contains { $0.id == "fixture-single" })
        XCTAssertTrue(room.discs.contains { $0.id == "fixture-ep" })
        XCTAssertTrue(room.discs.contains { $0.id == "fixture-single" })
    }
}
