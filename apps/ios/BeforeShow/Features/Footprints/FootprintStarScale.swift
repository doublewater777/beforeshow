import Foundation

/// 星空用哪种音阶来弹。五声音阶免费，随便按都好听；其余是 Pro。都从 C 起。
enum FootprintSkyScale: String, CaseIterable, Identifiable {
    case pentatonic
    case major
    case minor
    case miyakoBushi
    case blues

    static let storageKey = "footprintSkyScale"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pentatonic: BSLocalization.text("五声音阶")
        case .major: BSLocalization.text("大调")
        case .minor: BSLocalization.text("小调")
        case .miyakoBushi: BSLocalization.text("都节音阶")
        case .blues: BSLocalization.text("布鲁斯")
        }
    }

    var isPro: Bool { self != .pentatonic }

    /// Degrees within an octave.
    var steps: [Int] {
        switch self {
        case .pentatonic: [0, 2, 4, 7, 9]
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10]
        case .miyakoBushi: [0, 1, 5, 7, 8]
        case .blues: [0, 3, 5, 6, 7, 10]
        }
    }

    /// 存下的音阶；Pro 失效后回到五声音阶，选择本身留着，续费后恢复。
    static func effective(_ rawValue: String, isPro: Bool) -> FootprintSkyScale {
        guard let scale = FootprintSkyScale(rawValue: rawValue), !scale.isPro || isPro else { return .pentatonic }
        return scale
    }
}

/// The sky as an instrument: stars are tuned left to right like a keyboard. The free pentatonic
/// scale lets any stars pressed together still sound good.
enum FootprintStarScale {
    /// C4: phone speakers barely carry anything lower.
    private static let lowest = 60

    /// MIDI note for a point `fraction` of the way across the sky, left to right.
    static func note(across fraction: Double, scale: FootprintSkyScale = .pentatonic) -> Int {
        note(rank: Int((min(1, max(0, fraction)) * 100).rounded()), of: 101, scale: scale)
    }

    /// MIDI note for the star at `rank` (0 = leftmost) among `count` stars.
    static func note(rank: Int, of count: Int, scale: FootprintSkyScale = .pentatonic) -> Int {
        let steps = scale.steps
        // Two octaves and a little more on every scale keeps the top bright without getting shrill.
        let range = steps.count * 2 + 3
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
            ("add9", [0, 2, 4, 7]), ("5", [0, 7]),
            // 五声音阶里其余的组合也都有名字：缺音的和弦按它最像的那个叫，任意几颗星都能拼成和弦。
            ("", [0, 4]), ("m", [0, 3]), ("sus2", [0, 2]),
            ("add9", [0, 2, 4]), ("6", [0, 7, 9]), ("m7", [0, 7, 10]),
            ("6/9", [0, 2, 4, 9]), ("7sus4", [0, 5, 7, 10]), ("6/9", [0, 2, 4, 7, 9]),
            // 其他音阶里常见的。
            ("7", [0, 4, 7, 10]), ("maj7", [0, 4, 7, 11]), ("dim", [0, 3, 6]), ("m7♭5", [0, 3, 6, 10])
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
