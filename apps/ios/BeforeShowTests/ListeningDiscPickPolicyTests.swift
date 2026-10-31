import XCTest
@testable import BeforeShow

final class ListeningDiscPickPolicyTests: XCTestCase {
    func testUnchangedCandidatesCanStartWithEveryDisc() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = (0..<8).map { sampleDisc("d\($0)", songIDs: ["s\($0)"]) }
        var starts = Set<String>()
        var generator = SeededGenerator(state: 42)

        for _ in 0..<128 {
            let picked = try XCTUnwrap(ListeningDiscPickPolicy.pick(
                showID: showID, scopeKey: "all", candidates: discs,
                defaults: defaults, using: &generator
            ))
            starts.insert(picked.id)
        }

        XCTAssertEqual(starts, Set(discs.map(\.id)), "Starting disc must not be fixed by score or stable hash")
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
            excluding: [],
            defaults: defaults
        )
        XCTAssertNotEqual(second?.id, "b")
        XCTAssertTrue(["a", "c"].contains(second?.id ?? ""))
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
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "artist-1", discID: "b", defaults: defaults)

        let allPick = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            defaults: defaults
        )
        XCTAssertEqual(allPick?.id, "b")

        let artistPick = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "artist-1",
            candidates: discs,
            defaults: defaults
        )
        XCTAssertEqual(artistPick?.id, "a")
    }

    func testContinuousRedrawCompletesEveryRoundAndReshuffles() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let discs = (0..<8).map { sampleDisc("d\($0)", songIDs: ["s\($0)"]) }
        let candidateIDs = Set(discs.map(\.id))
        var generator = SeededGenerator(state: 123)

        var sessionExcluded: Set<String> = []
        var current = try XCTUnwrap(ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: discs,
            excluding: sessionExcluded,
            defaults: defaults,
            using: &generator
        ))
        ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: current.id, defaults: defaults)

        var drawnOrder = [current.id]

        for _ in 1..<24 {
            sessionExcluded.insert(current.id)
            if candidateIDs.isSubset(of: sessionExcluded) {
                sessionExcluded = []
            }
            let next = try XCTUnwrap(ListeningDiscPickPolicy.pick(
                showID: showID,
                scopeKey: "all",
                candidates: discs,
                excluding: sessionExcluded,
                defaults: defaults,
                using: &generator
            ))
            XCTAssertNotEqual(next.id, current.id, "Consecutive redraws must never repeat the same disc")
            ListeningDiscPickPolicy.recordDraw(showID: showID, scopeKey: "all", discID: next.id, defaults: defaults)
            drawnOrder.append(next.id)
            current = next
        }

        for start in stride(from: 0, to: 24, by: discs.count) {
            XCTAssertEqual(Set(drawnOrder[start..<(start + discs.count)]), candidateIDs)
        }
        XCTAssertNotEqual(Array(drawnOrder[0..<8]), Array(drawnOrder[8..<16]), "New rounds reshuffle")
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
            excluding: ["album"],
            defaults: defaults
        )
        XCTAssertEqual(pickedSingle?.id, "single", "Singles must remain in the candidate pool")

        let pickedComp = ListeningDiscPickPolicy.pick(
            showID: showID,
            scopeKey: "all",
            candidates: [compilation, album],
            excluding: ["album"],
            defaults: defaults
        )
        XCTAssertEqual(pickedComp?.id, "comp", "Live rehearsal compilations must be in the candidate pool")
    }

    func testReleaseFilterSeparatesAlbumsFromSinglesAndEPs() {
        let album = sampleDisc("album", songIDs: ["a"])
        let single = sampleDisc("single", songIDs: ["s"], isSingle: true)
        let ep = ListeningDisc(id: "ep", title: "Night - EP", artworkURL: nil,
                               tracks: album.tracks, isSingle: false)
        let unknown = ListeningDisc(id: "unknown", title: "Short Album", artworkURL: nil,
                                    tracks: album.tracks)
        let compilation = sampleDisc("live", songIDs: ["l"], origin: .compilation(showID: UUID(), number: 1))
        let playlist = sampleDisc("playlist", songIDs: ["p"], origin: .featuredPlaylist(artistID: "artist"))
        let discs = [album, single, ep, unknown, compilation, playlist]

        XCTAssertEqual(discs.filter(ListeningDiscPickFilter.all.includes).map(\.id), discs.map(\.id))
        XCTAssertEqual(discs.filter(ListeningDiscPickFilter.albums.includes).map(\.id), ["album", "unknown"])
        XCTAssertEqual(discs.filter(ListeningDiscPickFilter.singlesAndEPs.includes).map(\.id), ["single", "ep"])
        XCTAssertTrue([compilation, playlist].filter(ListeningDiscPickFilter.albums.includes).isEmpty)
    }

    func testEPFilterRecognizesCatalogSuffixWithoutGuessingFromTrackCount() {
        let track = sampleDisc("track", songIDs: ["s"]).tracks
        for title in ["Night - EP", "Night – EP", "Night — ep  "] {
            let disc = ListeningDisc(id: title, title: title, artworkURL: nil, tracks: track)
            XCTAssertTrue(ListeningDiscPickFilter.singlesAndEPs.includes(disc))
        }
        for title in ["EPIC", "Keep Going", "EP Collection"] {
            let disc = ListeningDisc(id: title, title: title, artworkURL: nil, tracks: track)
            XCTAssertFalse(ListeningDiscPickFilter.singlesAndEPs.includes(disc))
        }
    }

    func testEmptyCandidatesReturnNil() throws {
        let suite = "DiscPickPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let picked = ListeningDiscPickPolicy.pick(
            showID: UUID(),
            scopeKey: "all",
            candidates: [],
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

    func testRecentHistoryDoesNotForceSmallPoolToRepeatItsOrder() throws {
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

        var generator = SeededGenerator(state: 42)
        var pickedIDs = Set<String>()
        for _ in 0..<128 {
            let picked = try XCTUnwrap(ListeningDiscPickPolicy.pick(
                showID: showID, scopeKey: "all", candidates: discs,
                defaults: defaults, using: &generator
            ))
            pickedIDs.insert(picked.id)
        }
        XCTAssertEqual(pickedIDs, ["d0", "d1", "d2", "d3"], "Only the last draw is blocked across rounds")
        let key = "listening.discPick.\(showID.uuidString).all"
        let data = try XCTUnwrap(defaults.data(forKey: key))
        let history = try JSONDecoder().decode([String: [String]].self, from: data)
        XCTAssertEqual(history["recentIDs"], ["d2", "d3", "d4"], "Existing stored format remains compatible")
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

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            return value ^ (value >> 31)
        }
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
