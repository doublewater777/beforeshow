import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningReminderRosterTests: XCTestCase {
    func testCachedRosterUsesWantedOrderExclusionsRealEvidenceAndTheVisibleCompilationIdentity() throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        show.artists[1].appleMusicArtistID = "b"
        show.artists.append(ArtistSlot(name: "D", avatarURL: nil, appleMusicArtistID: "d"))
        for id in ["b1", "d1"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: id))
        }
        let playlist = ListeningCatalogPlaylistPayload(playlistID: "b-essentials", name: "B 精选",
            artworkURL: nil, curatorName: nil, descriptionText: nil, appleMusicURL: nil, orderedTrackIDs: ["b1"])
        context.insert(ArtistCatalogSnapshot(artistID: "b", artistName: "B", orderedSongIDs: ["b1"],
            topSongIDs: ["b1"], albumIDs: ["b-old", "b-single", "b-new"], featuredPlaylists: [playlist]))
        context.insert(ArtistCatalogSnapshot(artistID: "d", artistName: "D", orderedSongIDs: ["d1"], topSongIDs: ["d1"]))
        for (id, stamp, single) in [("b-old", 100.0, false), ("b-single", 300.0, true), ("b-new", 200.0, false)] {
            context.insert(CatalogAlbum(appleMusicAlbumID: id, title: id, releaseDate: Date(timeIntervalSince1970: stamp),
                artistIDs: ["b"], isSingle: single, orderedTrackIDs: ["b1"]))
        }
        let start = ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = try TimetablePerformance(artistName: "C", startsAt: start, endsAt: start.addingTimeInterval(1000), appleMusicArtistID: "c")
        c.isInterested = true
        let b = try TimetablePerformance(artistName: "B", startsAt: start.addingTimeInterval(2000),
            endsAt: start.addingTimeInterval(3000), appleMusicArtistID: "b")
        b.isInterested = true
        show.timetable = try Timetable(timeZoneIdentifier: "UTC", days: [
            TimetableDay(date: calendar.startOfDay(for: start), stages: [TimetableStage(name: "主舞台", performances: [b, c])])
        ])
        let repository = ListeningRepository(modelContext: context)
        try repository.setArtistExcluded(showID: show.id, artistID: "d", isExcluded: true)
        try repository.confirmActualFamiliarity(songID: "a2", at: start)
        try repository.confirmManualFamiliarity(songID: "a1", at: start)
        let playedAt = start.addingTimeInterval(-100)
        context.insert(ShowRecentListening(showID: show.id, discID: "album", songID: "a2", playedAt: playedAt))
        try context.save()

        let roster = try ListeningReminderRosterReader.read(show: show, in: context)
        XCTAssertEqual(roster.artists.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(roster.artists.first { $0.id == "b" }?.albums.map(\.id), ["b-new", "b-old"])
        XCTAssertEqual(roster.artists.first { $0.id == "b" }?.featuredPlaylist?.id, "b-essentials")
        XCTAssertFalse(roster.completedDiscIDs.contains("album"), "Manual familiarity is not actual listening")
        XCTAssertEqual(roster.lastListenedAt, playedAt)
        let room = ListenTestData.room(context)
        defer { room.stopHardwareMotion() }
        room.prepareForDisplay(show: show)
        XCTAssertNotNil(roster.singalong)
        XCTAssertTrue(room.compilationDiscs.contains { $0.id == roster.singalong?.id })
        XCTAssertNotNil(roster.wanted)
        XCTAssertTrue(room.compilationDiscs.contains { $0.id == roster.wanted?.id })
        XCTAssertFalse(room.compilationDiscs.flatMap(\.tracks).contains { $0.id == "d1" })
        room.excludeArtist("d", excluded: false)
        XCTAssertTrue(room.compilationDiscs.flatMap(\.tracks).contains { $0.id == "d1" })
        room.excludeArtist("d", excluded: true)
        XCTAssertFalse(room.compilationDiscs.flatMap(\.tracks).contains { $0.id == "d1" })

        try repository.confirmActualFamiliarity(songID: "a1", at: start)
        try context.save()
        XCTAssertTrue(try ListeningReminderRosterReader.read(show: show, in: context).completedDiscIDs.contains("album"))
    }
}
