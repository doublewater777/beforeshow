import XCTest
@testable import BeforeShow

final class ListeningDiscPickPolicyTests: XCTestCase {
    func testPickPrefersHigherUnexploredRatio() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let familiar = sampleDisc("familiar", songIDs: ["a", "b"])
        let unexplored = sampleDisc("unexplored", songIDs: ["c", "d"])

        let picked = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: [familiar, unexplored],
            familiarSongIDs: ["a", "b"],
            defaults: defaults
        )

        XCTAssertEqual(picked?.id, "unexplored")
    }

    func testPickExcludesRecentAndSessionIDsThenFallsBack() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = [
            sampleDisc("a", songIDs: ["a1"]),
            sampleDisc("b", songIDs: ["b1"]),
            sampleDisc("c", songIDs: ["c1", "c2"]),
        ]

        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: "a", defaults: defaults)
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: "b", defaults: defaults)

        let first = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            familiarSongIDs: ["a1", "b1"],
            excluding: ["c"],
            defaults: defaults
        )
        XCTAssertNotNil(first, "When every candidate is excluded, fall back to the full pool")
        XCTAssertNotEqual(first?.id, "c", "Should not pick the excluded disc c if other discs exist")
        XCTAssertTrue(["a", "b"].contains(first?.id ?? ""))

        let second = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            familiarSongIDs: ["a1", "b1"],
            excluding: [],
            defaults: defaults
        )
        XCTAssertEqual(second?.id, "c")
    }

    func testRedrawExhaustionDoesNotRepeatCurrentDisc() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = [
            sampleDisc("a", songIDs: ["a1"]),
            sampleDisc("b", songIDs: ["b1"]),
        ]

        // Both discs are in recent history
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: "a", defaults: defaults)
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: "b", defaults: defaults)

        // Currently viewing "b", tapping redraw excludes "b"
        let next = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            familiarSongIDs: [],
            excluding: ["b"],
            defaults: defaults
        )
        XCTAssertEqual(next?.id, "a", "Must not repeat the current disc b when redraw is requested")
    }

    func testRecentRingsAreIsolatedByScope() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = [
            sampleDisc("a", songIDs: ["a1", "a2"]),
            sampleDisc("b", songIDs: ["b1"]),
        ]

        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: "a", defaults: defaults)

        let allPick = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            familiarSongIDs: [],
            defaults: defaults
        )
        XCTAssertEqual(allPick?.id, "b")

        let artistPick = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "artist-1",
            candidates: discs,
            familiarSongIDs: ["b1"],
            defaults: defaults
        )
        XCTAssertEqual(artistPick?.id, "a")
    }

    func testContinuousRedrawCyclesAndLoopsFromBeginning() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = [
            sampleDisc("d1", songIDs: ["s1"]),
            sampleDisc("d2", songIDs: ["s2"]),
            sampleDisc("d3", songIDs: ["s3"]),
        ]
        let candidateIDs = Set(discs.map(\.id))

        var sessionExcluded: Set<String> = []
        var current = try XCTUnwrap(ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            familiarSongIDs: [],
            excluding: sessionExcluded,
            defaults: defaults
        ))
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: current.id, defaults: defaults)

        var drawnOrder = [current.id]

        for _ in 1...6 {
            sessionExcluded.insert(current.id)
            if candidateIDs.isSubset(of: sessionExcluded) {
                sessionExcluded = [current.id]
            }
            let next = try XCTUnwrap(ListeningDiscPickPolicy.pick(
                showID: showID,
                scopeKey: "all",
                candidates: discs,
                familiarSongIDs: [],
                excluding: sessionExcluded,
                defaults: defaults
            ))
            XCTAssertNotEqual(next.id, current.id, "Consecutive redraws must never repeat the same disc")
            ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: next.id, defaults: defaults)
            drawnOrder.append(next.id)
            current = next
        }

        XCTAssertEqual(Set(drawnOrder[0..<3]), candidateIDs)
        XCTAssertEqual(Set(drawnOrder[3..<6]), candidateIDs)
    }

    func testPoolIncludesSinglesCompilationsAndAlbums() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let album = sampleDisc("album", songIDs: ["a1"])
        let single = sampleDisc("single", songIDs: ["top"], isSingle: true)
        let compilation = sampleDisc("comp", songIDs: ["c1", "c2"], origin: .compilation(showID: showID, number: 1))

        let pickedSingle = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "artist",
            candidates: [single, album],
            familiarSongIDs: [],
            topSongIDs: ["top"],
            defaults: defaults
        )
        XCTAssertEqual(pickedSingle?.id, "single", "Singles must be included in the pool and scored fairly")

        let pickedComp = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: [compilation, album],
            familiarSongIDs: [],
            excluding: ["album"],
            defaults: defaults
        )
        XCTAssertEqual(pickedComp?.id, "comp", "Live rehearsal compilations must be in the candidate pool")
    }

    func testEmptyCandidatesReturnNil() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let picked = ListeningDiscPickPolicy.pick(
            showID: UUID(),
            scopeKey: "all",
            candidates: [],
            familiarSongIDs: [],
            defaults: defaults
        )
        XCTAssertNil(picked)
    }

    func testClearDrawsRemovesPersistedRings() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: "a", defaults: defaults)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("listening.discPick.")
        })

        ListeningDiscPickPolicy.clearDraws(defaults: defaults)
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("listening.discPick.")
        })
    }

    func testRecordDrawAppendsAndCapsRecentRing() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = (0..<5).map { sampleDisc("d\($0)", songIDs: ["s\($0)"]) }

        for disc in discs {
            ListeningDiscPickPolicy.recordDraw(
                showID: showID, scopeKey: "all", discID: disc.id, defaults: defaults
            )
        }

        let picked = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            familiarSongIDs: [],
            defaults: defaults
        )
        XCTAssertNotNil(picked)
        XCTAssertFalse(["d2", "d3", "d4"].contains(picked?.id ?? ""), "Ring keeps the last three draws out")
    }

    func testScopeKeyMapsBrowseState() {
        XCTAssertEqual(ListeningDiscPickPolicy.scopeKey(for: .all), "all")
        XCTAssertEqual(ListeningDiscPickPolicy.scopeKey(for: .artist("abc")), "abc")
    }

    func testCandidatesForAllIncludeCompilationsAndConnectedArtists() {
        let showID = UUID()
        let live = sampleDisc(
            "live",
            songIDs: ["l1"],
            origin: .compilation(showID: showID, number: 1)
        )
        let connected = sampleDisc("connected", songIDs: ["c1"])
        let disconnected = sampleDisc("disconnected", songIDs: ["d1"])
        let groups = [
            ListeningRackGroup(
                id: "live",
                kind: .live,
                name: "Live",
                artworkURL: nil,
                discs: [live]
            ),
            ListeningRackGroup(
                id: "slot-0",
                kind: .artist(id: "a", slotIndex: 0, isConnected: true),
                name: "A",
                artworkURL: nil,
                discs: [connected]
            ),
            ListeningRackGroup(
                id: "slot-1",
                kind: .artist(id: "b", slotIndex: 1, isConnected: false),
                name: "B",
                artworkURL: nil,
                discs: [disconnected]
            ),
        ]

        let all = ListeningDiscPickCandidates.discs(in: groups, scope: .all)
        XCTAssertEqual(all.map(\.id), ["live", "connected"])

        let artist = ListeningDiscPickCandidates.discs(in: groups, scope: .artist("a"))
        XCTAssertEqual(artist.map(\.id), ["connected"])
    }

    private func sampleDisc(
        _ id: String,
        songIDs: [String],
        isSingle: Bool = false,
        origin: ListeningDisc.Origin = .album
    ) -> ListeningDisc {
        ListeningDisc(
            id: id,
            title: id,
            artworkURL: URL(string: "https://example.com/\(id).png"),
            tracks: songIDs.map {
                ListeningDiscTrack(CatalogSong(appleMusicSongID: $0, title: $0, artistName: "Artist"))
            },
            isSingle: isSingle,
            origin: origin
        )
    }
}
