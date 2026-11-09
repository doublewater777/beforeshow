import XCTest
@testable import BeforeShow

final class FootprintStarScaleTests: XCTestCase {
    func testStarsAreTunedLeftToRightOnThePentatonicScale() {
        let notes = (0..<20).map { FootprintStarScale.note(rank: $0, of: 20) }
        XCTAssertEqual(notes, notes.sorted(), "further right never sounds lower")
        XCTAssertEqual(notes.first, 60, "the leftmost star is C4, high enough for a phone speaker")
        let pentatonic: Set<Int> = [0, 2, 4, 7, 9]
        XCTAssert(notes.allSatisfy { pentatonic.contains($0 % 12) }, "every note sits on C major pentatonic")
        XCTAssertEqual(FootprintStarScale.name(of: 60), "C")
        XCTAssertEqual(FootprintStarScale.note(across: 0), 60)
        XCTAssertLessThan(FootprintStarScale.note(across: 0.3), FootprintStarScale.note(across: 0.9))
        XCTAssertEqual(FootprintStarScale.frequency(of: 69), 440, accuracy: 0.001)
    }

    func testHeldNotesAreNamedAsAChordFromTheBass() {
        XCTAssertEqual(FootprintStarScale.chord(of: [48, 52, 55]), "C")
        XCTAssertEqual(FootprintStarScale.chord(of: [57, 60, 64]), "Am")
        XCTAssertEqual(FootprintStarScale.chord(of: [57, 60, 64, 67]), "Am7")
        XCTAssertEqual(FootprintStarScale.chord(of: [48, 52, 55, 57]), "C6")
        XCTAssertEqual(FootprintStarScale.chord(of: [48, 50, 55]), "Csus2")
        XCTAssertNil(FootprintStarScale.chord(of: [48]), "one note is not a chord")
    }

    func testEachScaleTunesTheSkyLeftToRightFromC4() {
        for scale in FootprintSkyScale.allCases {
            let notes = (0..<30).map { FootprintStarScale.note(rank: $0, of: 30, scale: scale) }
            XCTAssertEqual(notes, notes.sorted(), "\(scale)")
            XCTAssertEqual(notes.first, 60, "\(scale)")
            XCTAssertLessThanOrEqual(notes.last ?? 0, 89, "\(scale) stays below a shrill top")
            XCTAssert(notes.allSatisfy { scale.steps.contains($0 % 12) }, "\(scale)")
        }
        XCTAssertEqual(Set((0..<30).map { FootprintStarScale.note(rank: $0, of: 30, scale: .major) % 12 }), [0, 2, 4, 5, 7, 9, 11])
    }

    func testProScalesFallBackToPentatonicWithoutPro() {
        XCTAssertEqual(FootprintSkyScale.effective("major", isPro: true), .major)
        XCTAssertEqual(FootprintSkyScale.effective("major", isPro: false), .pentatonic)
        XCTAssertEqual(FootprintSkyScale.effective("pentatonic", isPro: false), .pentatonic)
        XCTAssertEqual(FootprintSkyScale.effective("unknown", isPro: true), .pentatonic)
    }

    func testEveryPentatonicCombinationHasAName() {
        let scale = [60, 62, 64, 67, 69]
        for mask in 1..<(1 << scale.count) {
            let notes = scale.indices.filter { mask & (1 << $0) != 0 }.map { scale[$0] }
            guard notes.count >= 2 else { continue }
            XCTAssertNotNil(FootprintStarScale.chord(of: notes), "\(notes.map(FootprintStarScale.name(of:)))")
        }
        XCTAssertEqual(FootprintStarScale.chord(of: [60, 64]), "C")
        XCTAssertEqual(FootprintStarScale.chord(of: [57, 60]), "Am")
        XCTAssertEqual(FootprintStarScale.chord(of: [60, 62]), "Csus2")
        XCTAssertEqual(FootprintStarScale.chord(of: [62, 69, 72]), "Dm7")
        XCTAssertEqual(FootprintStarScale.chord(of: [60, 62, 64, 67, 69]), "C6/9")
    }
}
