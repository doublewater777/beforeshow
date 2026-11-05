import Foundation

/// The sky as an instrument: stars are tuned left to right like a keyboard, on a pentatonic
/// scale so any stars pressed together still sound good.
enum FootprintStarScale {
    /// C major pentatonic degrees within an octave.
    private static let steps = [0, 2, 4, 7, 9]
    /// C4: phone speakers barely carry anything lower.
    private static let lowest = 60
    /// Two and a half octaves keeps the top bright without getting shrill.
    private static let range = 13

    /// MIDI note for a point `fraction` of the way across the sky, left to right.
    static func note(across fraction: Double) -> Int {
        note(rank: Int((min(1, max(0, fraction)) * 100).rounded()), of: 101)
    }

    /// MIDI note for the star at `rank` (0 = leftmost) among `count` stars.
    static func note(rank: Int, of count: Int) -> Int {
        let degree = count > 1 ? Int((Double(rank) / Double(count - 1) * Double(range - 1)).rounded()) : range / 2
        return lowest + 12 * (degree / steps.count) + steps[degree % steps.count]
    }

    static func frequency(of note: Int) -> Double {
        440 * pow(2, Double(note - 69) / 12)
    }

    static func name(of note: Int) -> String {
        ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"][((note % 12) + 12) % 12]
    }

    /// The chord the held notes make, named from the bass up when it can be: "C", "Am7", "Gsus2".
    static func chord(of notes: [Int]) -> String? {
        let classes = Set(notes.map { (($0 % 12) + 12) % 12 })
        guard classes.count >= 2, let bass = notes.min().map({ (($0 % 12) + 12) % 12 }) else { return nil }
        let shapes: [(suffix: String, intervals: Set<Int>)] = [
            ("", [0, 4, 7]), ("m", [0, 3, 7]),
            ("6", [0, 4, 7, 9]), ("m7", [0, 3, 7, 10]),
            ("sus2", [0, 2, 7]), ("sus4", [0, 5, 7]),
            ("add9", [0, 2, 4, 7]), ("5", [0, 7])
        ]
        let roots = [bass] + classes.subtracting([bass]).sorted()
        for root in roots {
            let intervals = Set(classes.map { ($0 - root + 12) % 12 })
            if let shape = shapes.first(where: { $0.intervals == intervals }) {
                return name(of: root) + shape.suffix
            }
        }
        return nil
    }
}
