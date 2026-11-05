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
}
