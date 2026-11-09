import XCTest
@testable import BeforeShow

final class FootprintStarSongTests: XCTestCase {
    func testTwinkleIsTheWholeSong() {
        let song = FootprintStarSong.twinkle
        XCTAssertEqual(song.steps.count, 42)
        XCTAssertEqual(song.steps.prefix(7).map(\.note), [60, 60, 67, 67, 69, 69, 67])
        XCTAssertEqual(song.steps.last, .init(note: 60, beats: 2))
    }

    func testEachScaleHasItsOwnSongAndSound() {
        let songs = FootprintSkyScale.allCases.map(FootprintStarSong.song(for:))
        XCTAssertEqual(Set(songs.map(\.title)).count, FootprintSkyScale.allCases.count)
        XCTAssertEqual(Set(FootprintSkyScale.allCases.map(\.timbre)).count, FootprintSkyScale.allCases.count)
        for song in songs {
            XCTAssertFalse(song.steps.isEmpty, song.title)
            XCTAssert(song.steps.allSatisfy { (55...88).contains($0.note) && $0.beats > 0 }, song.title)
        }
    }

    func testEverySongIsAccompaniedFromStartToEnd() {
        for scale in FootprintSkyScale.allCases {
            let song = FootprintStarSong.song(for: scale)
            XCTAssertEqual(song.chords.map(\.beats).reduce(0, +), song.steps.map(\.beats).reduce(0, +), song.title)
            XCTAssert(song.chords.contains { !$0.notes.isEmpty }, song.title)
        }
    }

    func testChordsAreVoicedLowEnoughToSitUnderTheMelody() {
        XCTAssertEqual(FootprintStarSong.chord("C", 1).notes, [60, 64, 67])
        XCTAssertEqual(FootprintStarSong.chord("Am", 1).notes, [57, 60, 64])
        XCTAssertEqual(FootprintStarSong.chord("G7", 1).notes, [55, 59, 62, 65])
        XCTAssertEqual(FootprintStarSong.chord("Esus4", 1).notes, [64, 69, 71])
        XCTAssertTrue(FootprintStarSong.chord("", 1).notes.isEmpty)
    }

    func testPentatonicAndSakuraSongsStayOnTheirScale() {
        XCTAssert(FootprintStarSong.jasmine.steps.allSatisfy { FootprintSkyScale.pentatonic.steps.contains($0.note % 12) })
        // 都节音阶从 E 起：E F A B C。
        XCTAssert(FootprintStarSong.sakura.steps.allSatisfy { [4, 5, 9, 11, 0].contains($0.note % 12) })
    }

    func testEachNoteLightsTheNearestStarPreferringNamedStars() {
        let notes = ["A": 64, "dust:0": 64, "B": 67, "dust:1": 65]
        let stars: Set<String> = ["A", "B"]
        XCTAssertEqual(FootprintStarSong.key(for: 64, notes: notes, stars: stars), "A")
        XCTAssertEqual(FootprintStarSong.key(for: 65, notes: notes, stars: stars), "dust:1")
        XCTAssertEqual(FootprintStarSong.key(for: 66, notes: ["A": 64, "B": 67], stars: stars), "B")
        XCTAssertNil(FootprintStarSong.key(for: 60, notes: [:], stars: stars))
    }
}
