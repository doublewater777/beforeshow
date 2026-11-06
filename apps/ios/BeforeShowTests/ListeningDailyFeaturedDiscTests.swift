import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import BeforeShow

@MainActor
final class ListeningDailyFeaturedDiscTests: XCTestCase {

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

    func testLiveCompilationFeaturedSleeveRotatesAcrossDays() throws {
        let suite = "DailyFeaturedDiscTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID(), calendar = utcCalendar()
        let discs = [
            sampleDisc("singalong", songIDs: ["top-1", "top-2"], origin: .compilation(showID: showID, number: 1)),
            sampleDisc("latest", songIDs: ["new"], origin: .compilation(showID: showID, number: 2)),
            sampleDisc("deep", songIDs: ["cut"], origin: .compilation(showID: showID, number: 3))
        ]

        let first = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: ListeningDailyFeaturedDiscPolicy.liveArtistID, discs: discs,
            topSongIDs: ["top-1", "top-2"], familiarSongIDs: [],
            now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(first, "singalong")
        let sameDay = ListeningDailyFeaturedDiscPolicy.featuredDiscID(
            showID: showID, artistID: ListeningDailyFeaturedDiscPolicy.liveArtistID, discs: discs,
            topSongIDs: ["new"], familiarSongIDs: ["top-1"],
            now: day(25, calendar: calendar), calendar: calendar, defaults: defaults
        )
        XCTAssertEqual(sameDay, "singalong", "Live preview must keep today's compilation sleeve")

        let picks = [25, 26, 27].compactMap { number in
            ListeningDailyFeaturedDiscPolicy.featuredDiscID(
                showID: showID, artistID: ListeningDailyFeaturedDiscPolicy.liveArtistID, discs: discs,
                topSongIDs: ["top-1", "top-2"], familiarSongIDs: [],
                now: day(number, calendar: calendar), calendar: calendar, defaults: defaults
            )
        }
        XCTAssertEqual(Set(picks).count, 3)

        let group = ListeningRackGroup(
            id: "live", kind: .live, name: "现场预习", artworkURL: nil,
            discs: discs, featuredDiscID: picks.last
        )
        XCTAssertEqual(group.head?.id, picks.last)
        XCTAssertEqual(group.discs.map(\.id), ["singalong", "latest", "deep"])
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

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ number: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: 12))!
    }

    private func sampleDisc(
        _ id: String,
        songIDs: [String],
        isSingle: Bool = false,
        origin: ListeningDisc.Origin = .album
    ) -> ListeningDisc {
        ListeningDisc(
            id: id, title: id, artworkURL: URL(string: "https://example.com/\(id).png"),
            tracks: songIDs.map {
                ListeningDiscTrack(CatalogSong(appleMusicSongID: $0, title: $0, artistName: "Artist"))
            },
            isSingle: isSingle,
            origin: origin
        )
    }

}
