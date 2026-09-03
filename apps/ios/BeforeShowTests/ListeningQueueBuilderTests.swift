import SwiftData
import XCTest
@testable import BeforeShow

final class ListeningQueueBuilderTests: XCTestCase {
    func testQueueUsesUnfamiliarFirstPerArtistThenRoundRobinWithGlobalDedupe() {
        let queue = ListeningQueueBuilder.build(
            artists: [
                ListeningQueueArtistInput(
                    artistID: "a",
                    orderedSongIDs: ["a-known", "shared", "a-new"]
                ),
                ListeningQueueArtistInput(
                    artistID: "b",
                    orderedSongIDs: ["b-new", "shared", "b-known"]
                )
            ],
            familiarSongIDs: ["a-known", "b-known"]
        )

        XCTAssertEqual(queue, [
            ListeningQueueEntry(artistID: "a", songID: "shared"),
            ListeningQueueEntry(artistID: "b", songID: "b-new"),
            ListeningQueueEntry(artistID: "a", songID: "a-new"),
            ListeningQueueEntry(artistID: "b", songID: "b-known"),
            ListeningQueueEntry(artistID: "a", songID: "a-known")
        ])
        XCTAssertEqual(Set(queue.map(\.songID)).count, queue.count)
    }

    func testQueuePreservesAppleMusicOrderWithinUnfamiliarAndFamiliarPartitions() {
        let queue = ListeningQueueBuilder.build(
            artists: [ListeningQueueArtistInput(
                artistID: "a",
                orderedSongIDs: ["known-1", "new-1", "new-2", "known-2"]
            )],
            familiarSongIDs: ["known-1", "known-2"]
        )

        XCTAssertEqual(queue.map(\.songID), ["new-1", "new-2", "known-1", "known-2"])
    }

    func testExcludedArtistAndRuntimeOnlyArtistScopeAreIndependentInputs() {
        let artists = [
            ListeningQueueArtistInput(artistID: "a", orderedSongIDs: ["a1"]),
            ListeningQueueArtistInput(artistID: "b", orderedSongIDs: ["b1"]),
            ListeningQueueArtistInput(artistID: "c", orderedSongIDs: ["c1"])
        ]

        XCTAssertEqual(
            ListeningQueueBuilder.build(
                artists: artists,
                familiarSongIDs: [],
                excludedArtistIDs: ["b"]
            ).map(\.artistID),
            ["a", "c"]
        )
        XCTAssertEqual(
            ListeningQueueBuilder.build(
                artists: artists,
                familiarSongIDs: [],
                onlyArtistID: "b"
            ).map(\.artistID),
            ["b"]
        )
        XCTAssertTrue(ListeningQueueBuilder.build(
            artists: artists,
            familiarSongIDs: [],
            excludedArtistIDs: ["b"],
            onlyArtistID: "b"
        ).isEmpty)
    }
}

@MainActor
final class ListeningQueueProviderTests: XCTestCase {
    func testProviderUsesShowArtistOrderCrossShowFamiliarityAndCurrentShowExclusions() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "Queue",
            date: now.addingTimeInterval(86_400),
            startTime: now.addingTimeInterval(86_400),
            artists: [
                ArtistSlot(name: "B", avatarURL: nil, appleMusicArtistID: "b"),
                ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a")
            ]
        )
        let otherShowID = UUID()
        context.insert(show)
        context.insert(ArtistCatalogSnapshot(
            artistID: "a",
            artistName: "A",
            orderedSongIDs: ["a-known", "a-new"]
        ))
        context.insert(ArtistCatalogSnapshot(
            artistID: "b",
            artistName: "B",
            orderedSongIDs: ["b-new", "shared"]
        ))
        context.insert(SongFamiliarityRecord(songID: "a-known", manualConfirmedAt: now))
        context.insert(ShowSetlistMemory(showID: otherShowID, catalogSongID: "shared"))
        try context.save()

        let provider = ListeningQueueProvider(modelContext: context)
        XCTAssertEqual(
            try provider.queue(showID: show.id),
            [
                ListeningQueueEntry(artistID: "b", songID: "b-new"),
                ListeningQueueEntry(artistID: "a", songID: "a-new"),
                ListeningQueueEntry(artistID: "b", songID: "shared"),
                ListeningQueueEntry(artistID: "a", songID: "a-known")
            ]
        )

        let repository = ListeningRepository(modelContext: context)
        try repository.setArtistExcluded(showID: show.id, artistID: "b", isExcluded: true)
        try context.save()
        XCTAssertEqual(
            try provider.queue(showID: show.id).map(\.artistID),
            ["a", "a"]
        )
    }
}
