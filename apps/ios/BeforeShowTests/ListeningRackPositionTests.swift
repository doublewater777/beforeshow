import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import BeforeShow

@MainActor
final class ListeningRackPositionTests: XCTestCase {
    func testMountingRackRestoresExpandedArtistWithoutResettingSavedAlbum() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
            .first { $0.artistID == "a" })
        snapshot.albumIDs.append("second-album")
        context.insert(CatalogAlbum(
            appleMusicAlbumID: "second-album", title: "Second Album",
            artistIDs: ["a"], orderedTrackIDs: ["a1"]
        ))
        try context.save()
        let room = ListenTestData.room(context)
        await room.load(show: show)
        defer { room.stop(); room.mechanism.motion.stop() }
        let group = try XCTUnwrap(room.rackGroups.first { $0.scope == .artist("a") })
        XCTAssertGreaterThan(group.discs.count, 1)
        let saved = ListeningRackPosition(showID: show.id)
        saved.expandedGroupID = group.id
        saved.focusedID = "\(group.id)#1"
        defer {
            UserDefaults.standard.removeObject(forKey: "listening.rackPosition.\(show.id.uuidString)")
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ListeningRackView(
            room: room, groups: room.rackGroups, scale: 1, onConnect: { _, _ in }
        ))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<20 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(room.browser.scope, .artist("a"))
        let restored = ListeningRackPosition(showID: show.id)
        XCTAssertEqual(restored.expandedGroupID, group.id)
        XCTAssertEqual(restored.focusedID, "\(group.id)#1")
    }


    func testFeaturedDiscRotatesAcrossDaysAndStaysFixedWithinDay() throws {
        let suite = "DailyFeaturedDiscTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID(), calendar = utcCalendar()
        let a = sampleDisc("a", songIDs: ["top-1", "top-2"])
        let b = sampleDisc("b", songIDs: ["other"])
        let albums = [a, b]

        let first = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: "artist", discs: albums,
            topSongIDs: ["top-1", "top-2"], familiarSongIDs: [],
            now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(first, "a")
        let sameDay = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: "artist",
            discs: albums + [sampleDisc("c", songIDs: ["top-3"])],
            topSongIDs: ["top-3"], familiarSongIDs: ["top-1", "top-2"],
            now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(sameDay, "a", "New catalog data and familiarity must not change today's sleeve")

        let nextDay = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: "artist", discs: albums,
            topSongIDs: ["top-1", "top-2"], familiarSongIDs: [],
            now: day(26, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(nextDay, "b")
        let thirdDay = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: "artist", discs: albums,
            topSongIDs: ["top-1", "top-2"], familiarSongIDs: [],
            now: day(27, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(thirdDay, "a")
    }

    func testFeaturedDiscKeepsReleaseOrderAndOnlyUsesSinglesAsFallback() throws {
        let suite = "DailyFeaturedDiscTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID(), calendar = utcCalendar()
        let a = sampleDisc("a", songIDs: ["song-a"])
        let b = sampleDisc("b", songIDs: ["song-b"])
        let single = sampleDisc("single", songIDs: ["top"], isSingle: true)
        let group = ListeningRackGroup(
            id: "slot-0", kind: .artist(id: "artist", slotIndex: 0, isConnected: true),
            name: "Artist", artworkURL: nil, discs: [a, b], featuredDiscID: "b"
        )
        XCTAssertEqual(group.head?.id, "b")
        XCTAssertEqual(group.discs.map(\.id), ["a", "b"])

        let picked = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: "artist", discs: [single, a],
            topSongIDs: ["top"], familiarSongIDs: [],
            now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(picked, "a", "An album outranks a single despite its popular track")
        let onlySingle = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: "single", discs: [single],
            topSongIDs: ["top"], familiarSongIDs: [],
            now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(onlySingle, "single")
    }

    func testThreeAlbumsAvoidThePreviousTwoChoices() throws {
        let suite = "DailyFeaturedDiscTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID(), calendar = utcCalendar()
        let discs = [
            sampleDisc("a", songIDs: ["top"]),
            sampleDisc("b", songIDs: ["b"]),
            sampleDisc("c", songIDs: ["c"])
        ]
        let picks = [25, 26, 27].compactMap { number in
            ListeningDailyFeaturedDiscPolicy.featuredDiscID(
                showID: showID, artistID: "artist", discs: discs,
                topSongIDs: ["top"], familiarSongIDs: [],
                now: day(number, calendar: calendar), calendar: calendar, defaults: defaults
            )
        }
        XCTAssertEqual(Set(picks).count, 3)
    }

    func testClearingLocalDataAlsoClearsSavedFeaturedSleeves() throws {
        let suite = "DailyFeaturedDiscTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID(), calendar = utcCalendar()
        let disc = sampleDisc("a", songIDs: ["top"])
        XCTAssertEqual(
            ListeningDailyFeaturedDiscPolicy.featuredDiscID(
                showID: showID, artistID: "artist", discs: [disc],
                topSongIDs: ["top"], familiarSongIDs: [],
                now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
            ),
            "a"
        )
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("listening.dailyFeatured.")
        })
        ListeningDailyFeaturedDiscPolicy.clearSelections(defaults: defaults)
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("listening.dailyFeatured.")
        })
    }

    func testCollapsedRackFocusExpiresAcrossDaysButExpandedFocusSurvives() throws {
        let suite = "DailyRackFocusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID(), key = "listening.rackPosition.\(showID.uuidString)"
        defaults.set(["focusedID": "slot-0#2", "focusedDay": "2000-1-1"], forKey: key)
        let collapsed = ListeningRackPosition(showID: showID, defaults: defaults)
        XCTAssertNil(collapsed.focusedID)

        defaults.set([
            "expandedGroupID": "slot-0", "focusedID": "slot-0#2", "focusedDay": "2000-1-1"
        ], forKey: key)
        let expanded = ListeningRackPosition(showID: showID, defaults: defaults)
        XCTAssertEqual(expanded.focusedID, "slot-0#2")
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ number: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: 12))!
    }

    private func sampleDisc(_ id: String, songIDs: [String], isSingle: Bool = false) -> ListeningDisc {
        ListeningDisc(
            id: id, title: id, artworkURL: URL(string: "https://example.com/\(id).png"),
            tracks: songIDs.map {
                ListeningDiscTrack(CatalogSong(appleMusicSongID: $0, title: $0, artistName: "Artist"))
            },
            isSingle: isSingle
        )
    }

    func testShelfPositionSurvivesRecreationAndIsSeparateForEachShow() throws {
        let suite = "ListeningRackPositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let position = ListeningRackPosition(showID: showID, defaults: defaults)
        XCTAssertNil(position.focusedID)
        XCTAssertNil(position.expandedGroupID)

        position.expandedGroupID = "artist-a"
        position.focusedID = "artist-a#3"

        let restored = ListeningRackPosition(
            showID: showID, defaults: try XCTUnwrap(UserDefaults(suiteName: suite))
        )
        XCTAssertEqual(restored.expandedGroupID, "artist-a")
        XCTAssertEqual(restored.focusedID, "artist-a#3")
        let otherShow = ListeningRackPosition(showID: UUID(), defaults: defaults)
        XCTAssertNil(otherShow.expandedGroupID)
        XCTAssertNil(otherShow.focusedID)

        restored.expandedGroupID = nil
        restored.focusedID = "artist-a#0"
        let collapsed = ListeningRackPosition(showID: showID, defaults: defaults)
        XCTAssertNil(collapsed.expandedGroupID)
        XCTAssertEqual(collapsed.focusedID, "artist-a#0")
    }
}
