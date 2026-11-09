import Foundation

/// 星空自己弹的歌，每种音阶一首，都是公版或传统旋律（布鲁斯是原创的一段）。
/// 音按真实音高弹，亮起的是音高最近的那颗星。
struct FootprintStarSong: Equatable {
    struct Step: Equatable {
        let note: Int
        let beats: Double
    }

    /// 伴奏的一个和弦；没有音的是休止。
    struct Chord: Equatable {
        let name: String
        let notes: [Int]
        let beats: Double
    }

    let title: String
    /// 一拍的秒数。
    let beat: TimeInterval
    let steps: [Step]
    /// 和旋律同时弹的和弦，总拍数和旋律一样。
    let chords: [Chord]

    /// 按和弦名排出三四个音，根音落在 G3 到 F#4 之间，手机喇叭也弹得出来。
    static func chord(_ name: String, _ beats: Double) -> Chord {
        let roots: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let first = name.first, let pitchClass = roots[first] else { return Chord(name: "", notes: [], beats: beats) }
        let quality = name.dropFirst()
        let intervals: [Int] = switch quality {
        case "m": [0, 3, 7]
        case "7": [0, 4, 7, 10]
        case "sus4": [0, 5, 7]
        case "5": [0, 7]
        default: [0, 4, 7]
        }
        let root = 55 + (pitchClass - 7 + 12) % 12
        return Chord(name: name, notes: intervals.map { root + $0 }, beats: beats)
    }

    private static func chords(_ pairs: [(String, Double)]) -> [Chord] {
        pairs.map { chord($0.0, $0.1) }
    }

    static func song(for scale: FootprintSkyScale) -> FootprintStarSong {
        switch scale {
        case .pentatonic: jasmine
        case .major: twinkle
        case .minor: greensleeves
        case .miyakoBushi: sakura
        case .blues: blues
        }
    }

    /// 这个音落在哪颗星上：音高最近的，同样近时有名字的星优先。
    static func key(for note: Int, notes: [String: Int], stars: Set<String>) -> String? {
        notes.min { lhs, rhs in
            let l = (abs(lhs.value - note), stars.contains(lhs.key) ? 0 : 1, lhs.key)
            let r = (abs(rhs.value - note), stars.contains(rhs.key) ? 0 : 1, rhs.key)
            return l < r
        }?.key
    }

    private static func steps(_ pairs: [(Int, Double)]) -> [Step] {
        pairs.map { Step(note: $0.0, beats: $0.1) }
    }

    // MARK: Songs

    /// 《小星星》，C 大调。
    static let twinkle: FootprintStarSong = {
        let c = 60, d = 62, e = 64, f = 65, g = 67, a = 69
        let line1 = [c, c, g, g, a, a, g]
        let line2 = [f, f, e, e, d, d, c]
        let line3 = [g, g, f, f, e, e, d]
        let notes = [line1, line2, line3, line3, line1, line2].flatMap { line in
            line.enumerated().map { Step(note: $0.element, beats: $0.offset == line.count - 1 ? 2 : 1) }
        }
        let harmony1: [(String, Double)] = [("C", 4), ("F", 2), ("C", 2)]
        let harmony2: [(String, Double)] = [("F", 2), ("C", 2), ("G", 2), ("C", 2)]
        let harmony3: [(String, Double)] = [("C", 2), ("F", 2), ("C", 2), ("G", 2)]
        let harmony = [harmony1, harmony2, harmony3, harmony3, harmony1, harmony2].flatMap { $0 }
        return FootprintStarSong(title: BSLocalization.text("小星星"), beat: 0.42, steps: notes, chords: chords(harmony))
    }()

    /// 《茉莉花》，C 五声音阶。
    static let jasmine: FootprintStarSong = {
        let do1 = 60, re = 62, mi = 64, so = 67, la = 69, do2 = 72
        let opening: [(Int, Double)] = [
            (mi, 1), (mi, 0.5), (so, 0.5), (la, 0.5), (do2, 0.5), (do2, 0.5), (la, 0.5),
            (so, 1), (so, 0.5), (la, 0.5), (so, 2)
        ]
        let rest: [(Int, Double)] = [
            (so, 1), (so, 1), (so, 1), (mi, 0.5), (so, 0.5),
            (la, 1), (la, 1), (so, 2),
            (mi, 1), (re, 0.5), (mi, 0.5), (so, 1), (mi, 0.5), (re, 0.5),
            (do1, 1), (do1, 0.5), (re, 0.5), (do1, 2)
        ]
        let openingHarmony: [(String, Double)] = [("C", 2), ("Am", 2), ("C", 4)]
        let restHarmony: [(String, Double)] = [("C", 4), ("Am", 2), ("C", 2), ("C", 2), ("G", 2), ("G", 2), ("C", 2)]
        return FootprintStarSong(
            title: BSLocalization.text("茉莉花"), beat: 0.5, steps: steps(opening + opening + rest),
            chords: chords(openingHarmony + openingHarmony + restHarmony)
        )
    }()

    /// 《绿袖子》，A 小调，按八分音符计拍。
    static let greensleeves: FootprintStarSong = {
        let e = 64, fs = 66, g = 67, gs = 68, a = 69, b = 71, c = 72, d = 74, e2 = 76, f2 = 77
        let first: [(Int, Double)] = [
            (a, 1), (c, 2), (d, 1), (e2, 1.5), (f2, 0.5), (e2, 1), (d, 2), (b, 1), (g, 1.5), (a, 0.5), (b, 1),
            (c, 2), (a, 1), (a, 1.5), (gs, 0.5), (a, 1), (b, 2), (gs, 1), (e, 2)
        ]
        let second: [(Int, Double)] = [
            (a, 1), (c, 2), (d, 1), (e2, 1.5), (f2, 0.5), (e2, 1), (d, 2), (b, 1), (g, 1.5), (a, 0.5), (b, 1),
            (c, 1.5), (b, 0.5), (a, 1), (gs, 1.5), (fs, 0.5), (gs, 1), (a, 3)
        ]
        // 起拍那一个八分音符不配和弦。
        let harmony: [(String, Double)] = [
            ("", 1), ("Am", 6), ("G", 6), ("Am", 6), ("E", 6),
            ("Am", 6), ("G", 6), ("Am", 3), ("E", 3), ("Am", 3)
        ]
        return FootprintStarSong(title: BSLocalization.text("绿袖子"), beat: 0.27, steps: steps(first + second), chords: chords(harmony))
    }()

    /// 《樱花》，都节音阶。
    static let sakura: FootprintStarSong = {
        let e = 64, f = 65, a = 69, b = 71, c = 72
        let call: [(Int, Double)] = [(a, 1), (a, 1), (b, 2), (a, 1), (a, 1), (b, 2)]
        let middle: [(Int, Double)] = [
            (a, 1), (b, 1), (c, 1), (b, 1), (a, 1), (b, 0.5), (a, 0.5), (f, 2),
            (e, 1), (c, 1), (e, 1), (f, 1), (e, 1), (e, 0.5), (c, 0.5), (b, 2)
        ]
        let ending: [(Int, Double)] = [(e, 1), (f, 1), (b, 0.5), (a, 0.5), (f, 1), (e, 4)]
        // 只用都节音阶里的音：Am、F、Esus4。
        let callHarmony: [(String, Double)] = [("Am", 4), ("Esus4", 4)]
        let middleHarmony: [(String, Double)] = [("Am", 4), ("F", 4), ("Am", 4), ("Esus4", 4)]
        let endingHarmony: [(String, Double)] = [("F", 4), ("Esus4", 4)]
        return FootprintStarSong(
            title: BSLocalization.text("樱花"), beat: 0.55, steps: steps(call + middle + middle + call + ending),
            chords: chords(callHarmony + middleHarmony + middleHarmony + callHarmony + endingHarmony)
        )
    }()

    /// 一段原创的十二小节布鲁斯，C 调。
    static let blues: FootprintStarSong = {
        func riff(_ root: Int) -> [(Int, Double)] {
            [(root, 0.5), (root + 3, 0.5), (root + 5, 0.5), (root + 6, 0.5), (root + 7, 1), (root + 3, 1), (root, 2), (root + 10, 1), (root + 7, 1)]
        }
        let c = 60, f = 65, g = 67
        let ending: [(Int, Double)] = [(g, 0.5), (g + 3, 0.5), (g + 5, 1), (f + 3, 0.5), (f, 0.5), (c + 3, 1), (c, 4)]
        let harmony: [(String, Double)] = [("C7", 8), ("C7", 8), ("F7", 8), ("C7", 8), ("G7", 2), ("F7", 2), ("C7", 4)]
        return FootprintStarSong(
            title: BSLocalization.text("星空布鲁斯"), beat: 0.4, steps: steps(riff(c) + riff(c) + riff(f) + riff(c) + ending),
            chords: chords(harmony)
        )
    }()
}

extension FootprintSkyScale {
    /// 每种音阶自己的声音。
    var timbre: FootprintStarSynth.Timbre {
        switch self {
        case .pentatonic: .celesta
        case .major: .musicBox
        case .minor: .softPiano
        case .miyakoBushi: .pluck
        case .blues: .electricPiano
        }
    }
}
