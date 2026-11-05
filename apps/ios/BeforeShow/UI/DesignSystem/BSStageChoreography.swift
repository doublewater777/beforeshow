import Foundation

/// What one moving head is doing at a moment.
struct BSStageBeamState: Equatable {
    /// Degrees from straight along the lamp's axis (down for the truss, up for the deck); negative points left.
    var pan: Double
    /// 1 aims along the axis; lower lifts a truss beam toward the crowd.
    var tilt: Double
    var intensity: Double
    var rgb: SIMD3<Double>
    /// Beam width multiplier.
    var spread: Double

    static let off = BSStageBeamState(pan: 0, tilt: 1, intensity: 0, rgb: SIMD3(repeating: 1), spread: 1)
}

/// A fan of thin laser lines from behind the top of the screen.
struct BSStageLaserState: Equatable {
    /// Where the fan points, in degrees from straight down.
    var center: Double
    /// Total opening of the fan in degrees.
    var opening: Double
    var intensity: Double
    var rgb: SIMD3<Double>

    static let off = BSStageLaserState(center: 0, opening: 0, intensity: 0, rgb: SIMD3(repeating: 1))
}

struct BSStageFrame: Equatable {
    /// Moving heads on the truss, left to right.
    var truss: [BSStageBeamState]
    /// Uplights on the stage deck, left to right.
    var deck: [BSStageBeamState]
    var laser: BSStageLaserState
}

/// A looping light programme run the way an operator runs a show. Each cue has its own
/// shape and colour idea: a curtain of white columns, deck lights fanning up, an X of
/// alternating colours, a chase, a ballyhoo over the crowd, a blackout into a laser hit,
/// and a focus on the screen.
///
/// Energy decides how much of it runs: at 0 only the still preset while the room fills,
/// more cues and faster movement as the show nears, the lasers only once it starts.
enum BSStageChoreography {
    static let beat = 0.5
    static let trussCount = 6
    static let deckCount = 4

    struct Fixture {
        let index: Int
        let count: Int
        let palette: [SIMD3<Double>]

        /// Position on the rig, -1 at the left end to 1 at the right.
        var p: Double { count > 1 ? Double(index) / Double(count - 1) * 2 - 1 : 0 }
        var isEven: Bool { index % 2 == 0 }
        var a: SIMD3<Double> { palette.first ?? BSStageChoreography.white }
        var b: SIMD3<Double> { palette.count > 1 ? palette[1] : a }
        var white: SIMD3<Double> { BSStageChoreography.white }
        /// Alternates the poster's two colours along the rig.
        var alternating: SIMD3<Double> { isEven ? a : b }
    }

    /// Cold white, the colour of a bare beam lamp.
    static let white = SIMD3<Double>(0.86, 0.92, 1)

    private struct Cue {
        /// The energies at which this cue is part of the programme.
        let energies: ClosedRange<Double>
        let duration: Double
        /// How long the move into this cue takes: short is a snap, long a crossfade.
        let entry: Double
        var truss: @Sendable (_ fixture: Fixture, _ time: Double) -> BSStageBeamState = { _, _ in .off }
        var deck: @Sendable (_ fixture: Fixture, _ time: Double) -> BSStageBeamState = { _, _ in .off }
        var laser: @Sendable (_ palette: [SIMD3<Double>], _ time: Double) -> BSStageLaserState = { _, _ in .off }
    }

    static func programmeLength(energy: Double) -> Double {
        programme(energy: energy).reduce(0) { $0 + $1.duration }
    }

    private static func programme(energy: Double) -> [Cue] {
        let running = allCues.filter { $0.energies.contains(min(1, max(0, energy))) }
        return running.isEmpty ? [allCues[0]] : running
    }

    static func frame(at time: Double, palette: [SIMD3<Double>], energy: Double = 1) -> BSStageFrame {
        let cues = programme(energy: energy)
        // Lamps move slower while the room is still filling.
        let time = time * (0.55 + 0.45 * min(1, max(0, energy)))
        let length = cues.reduce(0) { $0 + $1.duration }
        var local = time.truncatingRemainder(dividingBy: length)
        if local < 0 { local += length }
        var current = 0
        while current < cues.count - 1, local >= cues[current].duration {
            local -= cues[current].duration
            current += 1
        }
        let cue = cues[current]
        let previous = cues[(current + cues.count - 1) % cues.count]
        let weight = local < cue.entry ? ease(local / cue.entry) : 1
        let before = previous.duration + local

        func beams(_ count: Int, _ look: (Cue) -> (Fixture, Double) -> BSStageBeamState) -> [BSStageBeamState] {
            (0..<count).map { index in
                let fixture = Fixture(index: index, count: count, palette: palette)
                let now = look(cue)(fixture, local)
                guard weight < 1 else { return clamp(now) }
                return clamp(blend(look(previous)(fixture, before), now, weight))
            }
        }
        let laserNow = cue.laser(palette, local)
        let laser = weight < 1 ? blend(previous.laser(palette, before), laserNow, weight) : laserNow
        return BSStageFrame(
            truss: beams(trussCount) { $0.truss },
            deck: beams(deckCount) { $0.deck },
            laser: laser
        )
    }

    private static let allCues: [Cue] = [
        // Preset: the room is filling; the rig holds a gentle fan in the poster's colours and breathes.
        Cue(energies: 0...0.99, duration: 9, entry: 1.6, truss: { f, t in
            BSStageBeamState(pan: f.p * 10, tilt: 1, intensity: 0.42 + 0.14 * sin(t * 0.6 + Double(f.index) * 0.9), rgb: f.alternating, spread: 0.8)
        }, deck: { f, _ in
            BSStageBeamState(pan: f.p * 8, tilt: 1, intensity: 0.22, rgb: f.b, spread: 0.9)
        }),
        // Curtain: white columns straight down, coming on one by one.
        Cue(energies: 0.3...1, duration: 7, entry: 1.2, truss: { f, t in
            let on = ease((t - Double(f.index) * 0.35) / 0.6)
            return BSStageBeamState(pan: 0, tilt: 1, intensity: 0.1 + 0.85 * on, rgb: f.white, spread: 0.7)
        }),
        // Deck fan: the uplights open out in colour, changing shape every bar; the curtain dims behind.
        Cue(energies: 0.5...1, duration: 6, entry: 1, truss: { f, _ in
            BSStageBeamState(pan: 0, tilt: 1, intensity: 0.22, rgb: f.b, spread: 0.7)
        }, deck: { f, t in
            let shapes: [Double] = [28, 10, -14]
            let pan = stepped(t, every: beat * 4, move: 0.6) { f.p * shapes[$0 % shapes.count] }
            return BSStageBeamState(pan: pan, tilt: 1, intensity: 0.95, rgb: f.a, spread: 1)
        }),
        // Cross: neighbours lean opposite ways in alternating colours and sweep through each other.
        Cue(energies: 0.3...1, duration: 7, entry: 1, truss: { f, t in
            let lean: Double = f.isEven ? 1 : -1
            return BSStageBeamState(pan: lean * 24 * cos(t * 0.6), tilt: 1, intensity: 0.9, rgb: f.alternating, spread: 0.9)
        }, deck: { f, _ in
            BSStageBeamState(pan: -f.p * 20, tilt: 1, intensity: 0.55, rgb: f.white, spread: 0.8)
        }),
        // Chase: a white light runs along the colour rig and back, beat by beat.
        Cue(energies: 0.7...1, duration: 6, entry: 0.7, truss: { f, t in
            let run = max(2 * (f.count - 1), 1)
            let step = Int(t / beat) % run
            let lit = step < f.count ? step : run - step
            let distance = abs(f.index - lit)
            return BSStageBeamState(
                pan: f.p * 12, tilt: 1,
                intensity: distance == 0 ? 1 : (distance == 1 ? 0.35 : 0.14),
                rgb: distance == 0 ? f.white : f.b, spread: 0.6
            )
        }, deck: { f, _ in
            BSStageBeamState(pan: f.p * 10, tilt: 1, intensity: 0.2, rgb: f.a, spread: 0.8)
        }),
        // Ballyhoo: each head wanders on its own, lifting out over the crowd.
        Cue(energies: 0.5...1, duration: 8, entry: 1.4, truss: { f, t in
            let i = Double(f.index)
            let colors = [f.a, f.b, f.white]
            return BSStageBeamState(
                pan: 22 * sin(t * 0.55 + i * 1.3), tilt: 0.72 + 0.28 * sin(t * 0.8 + i * 2.1),
                intensity: 0.8, rgb: colors[f.index % colors.count], spread: 1
            )
        }),
        // Hit: a breath of dark, then white everywhere and the lasers open, settling into colour.
        Cue(energies: 1...1, duration: 6, entry: 0.7, truss: { f, t in
            let (dark, fade) = hit(t)
            let rgb = f.white * fade + f.alternating * (1 - fade)
            return BSStageBeamState(pan: f.p * 14, tilt: 1, intensity: dark ? 0.03 : 0.55 + 0.45 * fade, rgb: rgb, spread: 0.8)
        }, deck: { f, t in
            let (dark, fade) = hit(t)
            return BSStageBeamState(pan: f.p * 25, tilt: 1, intensity: dark ? 0 : 0.35 + 0.6 * fade, rgb: f.white, spread: 0.9)
        }, laser: { palette, t in
            let (dark, fade) = hit(t)
            let color = palette.count > 1 ? palette[1] : (palette.first ?? white)
            let after = max(0, t - beat * 2)
            return BSStageLaserState(
                center: 16 * sin(after * 1.3), opening: 20 + 40 * ease(after / 1.2),
                intensity: dark ? 0 : 0.55 + 0.35 * fade, rgb: color
            )
        }),
        // Focus: every head on the screen, breathing, the deck glowing low.
        Cue(energies: 0.3...1, duration: 7, entry: 1.4, truss: { f, t in
            BSStageBeamState(pan: -f.p * 24, tilt: 1, intensity: 0.6 + 0.25 * sin(t * 1.3), rgb: f.a, spread: 0.8)
        }, deck: { f, _ in
            BSStageBeamState(pan: -f.p * 18, tilt: 1, intensity: 0.3, rgb: f.b, spread: 0.9)
        })
    ]

    /// The blackout before a hit, then how much of the flash is left.
    private static func hit(_ t: Double) -> (dark: Bool, fade: Double) {
        let dark = t < beat * 2
        return (dark, dark ? 1 : exp(-(t - beat * 2) * 1.4))
    }

    /// A value that holds, then moves to its next position quickly, like a head hitting a new mark.
    private static func stepped(_ time: Double, every step: Double, move: Double, _ value: (Int) -> Double) -> Double {
        let segment = Int(floor(time / step))
        let into = time - Double(segment) * step
        let target = value(segment)
        guard segment > 0, into < move else { return target }
        return value(segment - 1) + (target - value(segment - 1)) * ease(into / move)
    }

    private static func ease(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    private static func blend(_ a: BSStageBeamState, _ b: BSStageBeamState, _ w: Double) -> BSStageBeamState {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * w }
        // A lamp that is off has no colour worth fading from.
        let fromColor = a.intensity < 0.01 ? b.rgb : a.rgb
        return BSStageBeamState(
            pan: mix(a.pan, b.pan),
            tilt: mix(a.tilt, b.tilt),
            intensity: mix(a.intensity, b.intensity),
            rgb: fromColor + (b.rgb - fromColor) * w,
            spread: mix(a.spread, b.spread)
        )
    }

    private static func blend(_ a: BSStageLaserState, _ b: BSStageLaserState, _ w: Double) -> BSStageLaserState {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * w }
        return BSStageLaserState(center: mix(a.center, b.center), opening: mix(a.opening, b.opening), intensity: mix(a.intensity, b.intensity), rgb: b.intensity > 0 ? b.rgb : a.rgb)
    }

    private static func clamp(_ state: BSStageBeamState) -> BSStageBeamState {
        BSStageBeamState(
            pan: min(30, max(-30, state.pan)),
            tilt: min(1, max(0.4, state.tilt)),
            intensity: min(1, max(0, state.intensity)),
            rgb: state.rgb.clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1)),
            spread: min(1.6, max(0.4, state.spread))
        )
    }
}
