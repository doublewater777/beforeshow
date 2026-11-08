import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ShowSetlistPhaseTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, ShowSetlistMemory.self, CatalogSong.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeShow(date: Date = Date()) throws -> Show {
        try Show(
            name: "告五人 宇宙的有趣",
            date: date,
            startTime: date,
            timeZoneIdentifier: "Asia/Shanghai",
            artists: [ArtistSlot(name: "告五人")]
        )
    }

    // MARK: - Model defaults & backward compatibility

    func testWasPlayedNilTreatedAsPlayed() {
        let showID = UUID()
        let memory = ShowSetlistMemory(
            showID: showID,
            catalogSongID: "song1",
            manualTitle: "爱人错过",
            manualArtistName: "告五人"
        )

        XCTAssertNil(memory.wasPlayed)
        XCTAssertTrue(memory.isPlayed, "nil wasPlayed must be treated as played for legacy records")
        XCTAssertNil(memory.order)
    }

    func testWasPlayedExplicitFalseAndTrue() {
        let showID = UUID()
        let unplayed = ShowSetlistMemory(
            showID: showID,
            manualTitle: "披星戴月的想你",
            manualArtistName: "告五人",
            wasPlayed: false,
            order: 1
        )
        XCTAssertEqual(unplayed.wasPlayed, false)
        XCTAssertFalse(unplayed.isPlayed)
        XCTAssertEqual(unplayed.order, 1)

        let played = ShowSetlistMemory(
            showID: showID,
            manualTitle: "给你一瓶魔法药水",
            manualArtistName: "告五人",
            wasPlayed: true,
            order: 2
        )
        XCTAssertEqual(played.wasPlayed, true)
        XCTAssertTrue(played.isPlayed)
        XCTAssertEqual(played.order, 2)
    }

    // MARK: - SwiftData Persistence & Roundtrip

    func testSwiftDataRoundtripPreservesWasPlayedAndOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)

        let legacy = ShowSetlistMemory(showID: show.id, manualTitle: "唯一", manualArtistName: "告五人")
        let unplayed = ShowSetlistMemory(showID: show.id, manualTitle: "带我去找夜生活", manualArtistName: "告五人", wasPlayed: false, order: 1)
        let played = ShowSetlistMemory(showID: show.id, manualTitle: "好不容易", manualArtistName: "告五人", wasPlayed: true, order: 2)

        [legacy, unplayed, played].forEach(context.insert)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ShowSetlistMemory>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(fetched.count, 3)

        let fetchedLegacy = try XCTUnwrap(fetched.first { $0.manualTitle == "唯一" })
        XCTAssertNil(fetchedLegacy.wasPlayed)
        XCTAssertTrue(fetchedLegacy.isPlayed)
        XCTAssertNil(fetchedLegacy.order)

        let fetchedUnplayed = try XCTUnwrap(fetched.first { $0.manualTitle == "带我去找夜生活" })
        XCTAssertEqual(fetchedUnplayed.wasPlayed, false)
        XCTAssertFalse(fetchedUnplayed.isPlayed)
        XCTAssertEqual(fetchedUnplayed.order, 1)

        let fetchedPlayed = try XCTUnwrap(fetched.first { $0.manualTitle == "好不容易" })
        XCTAssertEqual(fetchedPlayed.wasPlayed, true)
        XCTAssertTrue(fetchedPlayed.isPlayed)
        XCTAssertEqual(fetchedPlayed.order, 2)
    }

    // MARK: - Footprint archive only counts played songs

    func testFootprintArchiveExcludesUnplayedSongs() throws {
        let show = try makeShow()
        let legacy = ShowSetlistMemory(showID: show.id, manualTitle: "爱人错过", manualArtistName: "告五人") // nil -> played
        let played = ShowSetlistMemory(showID: show.id, manualTitle: "给你一瓶魔法药水", manualArtistName: "告五人", wasPlayed: true)
        let unplayed = ShowSetlistMemory(showID: show.id, manualTitle: "未唱曲目", manualArtistName: "告五人", wasPlayed: false)

        let songs = FootprintSetlistArchive.songs(
            memories: [legacy, played, unplayed],
            shows: [show]
        )

        let titles = songs.map(\.title)
        XCTAssertTrue(titles.contains("爱人错过"), "Legacy records (wasPlayed == nil) must be counted in archive")
        XCTAssertTrue(titles.contains("给你一瓶魔法药水"), "Played records must be counted in archive")
        XCTAssertFalse(titles.contains("未唱曲目"), "Unplayed songs (wasPlayed == false) must NOT be counted in archive")
        XCTAssertEqual(songs.count, 2)
    }

    func testFootprintListeningCoordinatorExcludesUnplayedSongs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)

        let played = ShowSetlistMemory(showID: show.id, manualTitle: "爱人错过", manualArtistName: "告五人", wasPlayed: true)
        let unplayed = ShowSetlistMemory(showID: show.id, manualTitle: "未唱曲目", manualArtistName: "告五人", wasPlayed: false)
        [played, unplayed].forEach(context.insert)
        try context.save()

        let coordinator = FootprintListeningCoordinator(context: context, show: show)
        coordinator.reload()

        let titles = coordinator.memories.map { coordinator.title($0) }
        XCTAssertEqual(titles, ["爱人错过"])
    }
}
