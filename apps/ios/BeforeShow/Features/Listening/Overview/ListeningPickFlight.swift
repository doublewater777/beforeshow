import CoreGraphics
import Foundation

/// 冲天抛洒 and 飘羽 as numbers: where every cover is on the field's own clock, and what a finger does to the field.
/// A finger eases the field to a stop and lifts the cover under it; letting go puts that album on show, growing out of
/// where the cover was.
struct ListeningPickFlight {
    /// One cover in one throw or one fall.
    struct ID: Hashable {
        let card: Int
        let round: Int
    }

    enum Target: Equatable {
        case onShow
        case cover(ID)
    }

    /// A cover at one moment.
    struct Cover {
        let id: ID
        /// The album it shows, before wrapping round the albums.
        let album: Int
        var center: CGPoint
        var side: CGFloat
        let seed: Int
        /// 0 → 1 through the throw or the fall.
        let progress: Double
        /// 0 for the farthest feather, 1 for anything near.
        var near: Double = 1
        /// Which way the album on show is thrown.
        var sway: Double = 0
        var opacity: Double = 1
        /// 1 when it is turned to face you, 0 while it tumbles or swings freely.
        var facing: Double = 0
        /// How far a feather is turned from facing you, in radians: in the screen's plane, tipped back, and swung aside.
        var turn: (roll: Double, pitch: Double, yaw: Double) = (0, 0, 0)
    }

    /// The cover the album on show grew out of, as it was let go.
    struct Catch: Equatable {
        let id: ID
        let album: Int
        let center: CGPoint
        let side: CGFloat
    }

    /// What the field is drawn for.
    struct Layout {
        let albums: Int
        /// The album on show.
        let current: Int
        let size: CGSize
        /// Reduced motion: everything held where it reads best.
        let isStill: Bool
    }

    let style: ListeningPickStyle
    private(set) var clock: Clock
    /// When the album on show came on, on the field's clock.
    private(set) var currentSince: Double
    private(set) var held: Target?
    private(set) var heldAt: Date?
    private(set) var caught: Catch?

    init(style: ListeningPickStyle, at date: Date) {
        self.style = style
        clock = Clock(at: date)
        currentSince = clock.time(at: date)
    }

    // MARK: - The hand

    /// How far back a landing finger looks: the frame on screen when it came down.
    static let seenAgo = 0.04
    /// How much bigger a held cover is.
    static let lift = 0.18

    /// A finger comes down: the field eases to a stop and the cover that was under it lifts.
    mutating func press(at point: CGPoint, in layout: Layout, date: Date) {
        hold(target(at: point, in: layout, date: date.addingTimeInterval(-Self.seenAgo)), at: date)
        clock.ease(to: 0, over: 0.25, at: date)
    }

    /// The finger moves on: the cover under it now lifts instead.
    mutating func slide(to point: CGPoint, in layout: Layout, date: Date) {
        hold(target(at: point, in: layout, date: date), at: date)
    }

    /// The finger lifts and the field gets going again. A held cover comes on show from where it is; returns its album.
    mutating func release(in layout: Layout, date: Date) -> Int? {
        let lifted = 1 + Self.lift * lifting(at: date, isStill: layout.isStill)
        defer {
            held = nil
            heldAt = nil
            clock.ease(to: 1, over: 0.6, at: date)
        }
        guard layout.albums > 0, case let .cover(id) = held,
              let cover = covers(in: layout, time: time(at: date, in: layout)).first(where: { $0.id == id }) else { return nil }
        let album = cover.album % layout.albums
        caught = Catch(id: id, album: album, center: cover.center, side: cover.side * lifted)
        currentSince = clock.time(at: date)
        return album
    }

    /// An album comes on show; unless a catch brought it, its throw or fall starts afresh.
    mutating func show(_ album: Int, date: Date) {
        guard caught?.album != album else { return }
        caught = nil
        currentSince = clock.time(at: date)
    }

    private mutating func hold(_ target: Target?, at date: Date) {
        guard target != held else { return }
        held = target
        heldAt = target == nil ? nil : date
    }

    /// 0 → 1 as a held cover lifts.
    func lifting(at date: Date, isStill: Bool) -> Double {
        guard let heldAt else { return 0 }
        if isStill { return 1 }
        let t = min(1, max(0, date.timeIntervalSince(heldAt)) / 0.15)
        return 1 - pow(1 - t, 3)
    }

    /// 0 → 1 as the field slows to a stop, turning every cover to face you.
    func facing(at date: Date) -> Double {
        Self.smoothstep(min(1, max(0, (0.7 - clock.rate(at: date)) / 0.7)))
    }

    /// The field's seconds at `date`.
    func time(at date: Date, in layout: Layout) -> Double {
        layout.isStill ? currentSince + (style == .toss ? Self.currentFlight * 0.5 : Self.currentFall * 0.3) : clock.time(at: date)
    }

    /// What a finger at `point` lands on, front first; nil where no cover is in sight.
    func target(at point: CGPoint, in layout: Layout, date: Date) -> Target? {
        // Covers fade out under the header and over the controls.
        guard layout.albums > 0, point.y > layout.size.height * 0.08, point.y < layout.size.height * 0.75 else { return nil }
        let time = time(at: date, in: layout)
        if Self.reaches(onShow(in: layout, time: time), point) { return .onShow }
        return covers(in: layout, time: time).reversed().first { Self.reaches($0, point) }.map { .cover($0.id) }
    }

    private static func reaches(_ cover: Cover, _ point: CGPoint) -> Bool {
        // At least a finger wide.
        let reach = max(cover.side, BSLayout.minTouchTarget) / 2
        return cover.opacity > 0.5 && abs(point.x - cover.center.x) <= reach && abs(point.y - cover.center.y) <= reach
    }

    // MARK: - Where everything is

    /// Every cover but the album on show, back to front.
    func covers(in layout: Layout, time: Double) -> [Cover] {
        let all = style == .toss
            ? (0..<Self.tossCards).map { Self.thrown($0, at: time, in: layout.size) }
            : Self.featherCards.map { Self.falling($0.card, near: $0.near, phase: $0.phase, at: time, in: layout.size) }
        return all.filter { $0.id != caught?.id }
    }

    /// The album on show. After a catch it grows, drifts and turns as one motion, from where the cover was let go into a
    /// flight of its own.
    func onShow(in layout: Layout, time: Double) -> Cover {
        let shown = max(0, time - currentSince)
        let size = layout.size
        guard let caught else { return flightOnShow(layout.current, after: shown, toward: nil, in: size) }
        let toward: Double = caught.center.x < size.width / 2 ? -1 : 1
        let lead = style == .toss
            ? Self.tossLead(rising: caught.center, current: layout.current, in: size)
            : Self.featherLead(at: caught.center, in: size)
        let start = flightOnShow(layout.current, after: lead, toward: toward, in: size)
        var cover = flightOnShow(layout.current, after: lead + shown, toward: toward, in: size)
        let settled = Self.smootherstep(min(1, shown / 0.9))
        cover.center.x += (caught.center.x - start.center.x) * (1 - settled)
        cover.center.y += (caught.center.y - start.center.y) * (1 - settled)
        cover.side = caught.side + (cover.side - caught.side) * settled
        cover.opacity = max(cover.opacity, 1 - settled)
        cover.facing = 1 - settled
        return cover
    }

    private func flightOnShow(_ current: Int, after shown: Double, toward: Double?, in size: CGSize) -> Cover {
        style == .toss
            ? Self.thrownOnShow(current, after: shown, toward: toward ?? (current.isMultiple(of: 2) ? 1 : -1), in: size)
            : Self.fallingOnShow(current, after: shown, in: size)
    }

    // MARK: - Toss

    private static let tossCards = 24
    /// Seconds from the spout to falling out of sight.
    private static let tossFlight = 4.5
    private static let currentFlight = 5.5

    /// Up a parabola from just below the screen to its peak, then down past where it started; each throw is new.
    private static func thrown(_ card: Int, at time: Double, in size: CGSize) -> Cover {
        let count = tossCards
        let base = min(size.height * 0.075, size.width * 0.16)
        let flight = time / tossFlight + (Double(card) + 0.6 * noise(card, 3)) / Double(count)
        let throwIndex = Int(flight.rounded(.down))
        let tau = flight - Double(throwIndex)
        let seed = card * 7 + throwIndex * 131
        let peak = size.height * mix(0.5, 0.88, noise(seed, 1).squareRoot()) + base * 0.3
        let spread = noise(seed, 2) * 2 - 1
        let drift = (spread < 0 ? -1 : 1) * pow(abs(spread), 0.8) * size.width * 0.56
        let depth = 1 / (1 - 0.08 * mix(-2.4, 1, noise(seed, 4)) * tau)
        let grown = 1 - pow(1 - min(1, tau / 0.38), 3)
        return Cover(
            id: ID(card: card, round: throwIndex),
            album: card + throwIndex * count,
            center: CGPoint(
                x: size.width / 2 + (noise(seed, 5) - 0.5) * 0.25 * base + drift * pow(tau, 0.8),
                y: size.height + base * 0.3 - arc(tau, peak: peak, drop: base * 1.2)
            ),
            side: mix(0.85, 1.12, noise(seed, 30)) * mix(0.38, 1, grown) * base * depth,
            seed: seed, progress: tau
        )
    }

    /// The album on show, thrown again and again: higher, slower and steadier than the rest, so it can be read. Each
    /// throw goes the other way, always clearly to one side; `toward` picks the side of the first.
    private static func thrownOnShow(_ current: Int, after shown: Double, toward: Double, in size: CGSize) -> Cover {
        let flight = shown / currentFlight
        let throwIndex = Int(flight.rounded(.down))
        let tau = flight - Double(throwIndex)
        let shape = throwShape(current, throwIndex: throwIndex, in: size)
        let lean = (throwIndex.isMultiple(of: 2) ? 1 : -1) * toward * mix(0.35, 1, noise(shape.seed, 2))
        return Cover(
            id: ID(card: -1, round: throwIndex),
            album: current,
            center: CGPoint(
                x: size.width / 2 + lean * size.width * 0.28 * pow(tau, 0.8),
                y: shape.spout - arc(tau, peak: shape.peak, drop: shape.drop)
            ),
            side: shape.full * mix(0.4, 1, 1 - pow(1 - min(1, tau / 0.3), 3)),
            seed: shape.seed, progress: tau, sway: lean
        )
    }

    private static func throwShape(_ current: Int, throwIndex: Int, in size: CGSize)
        -> (seed: Int, full: CGFloat, spout: CGFloat, peak: Double, drop: Double) {
        let seed = current * 13 + throwIndex * 131 + 5
        let full = min(size.height * 0.2, size.width * 0.4)
        let peak = Double(size.height) * mix(0.6, 0.74, noise(seed, 1)) + Double(full) * 0.5
        return (seed, full, size.height + full * 0.5, peak, Double(full) * 0.8)
    }

    /// Seconds into its first throw at which the album on show rises past `point`, or tops out below it.
    private static func tossLead(rising point: CGPoint, current: Int, in size: CGSize) -> Double {
        let shape = throwShape(current, throwIndex: 0, in: size)
        let launch = 2 * shape.peak + 2 * (shape.peak * shape.peak + shape.peak * shape.drop).squareRoot()
        let fall = launch + shape.drop
        let height = Double(shape.spout - point.y)
        let discriminant = launch * launch - 4 * fall * height
        let tau = discriminant > 0 ? (launch - discriminant.squareRoot()) / (2 * fall) : launch / (2 * fall)
        return max(0, tau) * currentFlight
    }

    /// Height above the spout along a parabola that peaks at `peak` and ends `drop` below where it started.
    private static func arc(_ tau: Double, peak: Double, drop: Double) -> Double {
        let launch = 2 * peak + 2 * (peak * peak + peak * drop).squareRoot()
        return launch * tau - (launch + drop) * tau * tau
    }

    // MARK: - Feathers

    /// One loop; near feathers fall three times in it, middle ones twice, far ones once.
    private static let featherLoop = 24.0
    /// Seconds for the album on show to fall and be carried back up; it falls for the first two thirds.
    private static let currentFall = 12.0
    private static let currentFalling = 0.68

    /// Far, middle and near. Only the far layer is softened, once as a whole, so every cover can still be read.
    static let featherLayers: [(lower: Double, upper: Double, blur: CGFloat)] = [(0, 0.36, 0.8), (0.36, 0.72, 0), (0.72, 1, 0)]

    /// Every feather far layer first, in drawing order. A layer's feathers are spaced evenly down the fall, so the field
    /// never empties.
    private static let featherCards: [(card: Int, near: Double, phase: Double)] = featherLayers.flatMap { depth in
        let cards = (0..<18).filter { depth.lower <= nearness($0) && nearness($0) < depth.upper }
        return cards.enumerated().map { rank, card in
            (card: card, near: nearness(card), phase: (Double(rank) + 0.5 * noise(card, 3)) / Double(cards.count))
        }
    }

    /// 0 for the farthest layer, nearly 1 for the nearest.
    private static func nearness(_ card: Int) -> Double {
        let x = Double(card) * 0.4142 + 0.17 + 0.25 * noise(card, 1)
        return x - x.rounded(.down)
    }

    /// Falls the screen while swinging side to side, quickest through the middle of a swing and tipping up at its ends.
    private static func falling(_ card: Int, near: Double, phase: Double, at time: Double, in size: CGSize) -> Cover {
        let falls: Double = near > 0.72 ? 3 : near > 0.36 ? 2 : 1
        let side = mix(0.85, 1.05, noise(card, 2)) * min(size.height * 0.13, size.width * 0.28) * mix(0.72, 1, near)
        let fall = time / featherLoop * falls + phase
        let fallen = fall - fall.rounded(.down)
        let margin = side * 0.9 + 10
        let swings: Double = falls == 3 ? Double(1 + card % 2) : Double(1 + card % 3)
        let offset = noise(card, 4) * 2 * .pi
        let angle = 2 * .pi * swings * fallen + offset
        let swing = sin(angle)
        let lane = Double(card) * 0.7548 + 0.11
        return Cover(
            id: ID(card: card, round: Int(fall.rounded(.down))),
            album: card,
            center: CGPoint(
                x: size.width / 2 + (lane - lane.rounded(.down) - 0.5) * size.width * 0.85 + 0.58 * side * swing,
                y: -margin + fallen * (size.height + 2 * margin) + 0.15 * side * (swing * swing - 0.5)
            ),
            side: side, seed: card, progress: fallen, near: near,
            // Turned only a little, so it can be read as it swings.
            turn: (
                roll: 0.22 * swing,
                pitch: 0.22 * (swing * swing - 0.4) + 0.06 * sin(2 * angle + offset + 0.5 * cos(angle)) - 0.06,
                yaw: 0.3 * swing * abs(swing)
            )
        )
    }

    /// The album on show drifting in front, larger, slower and calmer than the rest. It falls swinging through the
    /// middle of the screen, then a breeze sweeps it back up to one side, so it moves on without a break and stays in sight.
    private static func fallingOnShow(_ current: Int, after shown: Double, in size: CGSize) -> Cover {
        let side = min(size.height * 0.24, size.width * 0.5)
        let cycle = shown / currentFall
        let round = Int(cycle.rounded(.down))
        let phase = cycle - Double(round)
        // 0 at the top, 1 at the bottom, easing to a stop at both ends of the fall and of the lift.
        let depth = phase < currentFalling
            ? (1 - cos(.pi * phase / currentFalling)) / 2
            : (1 + cos(.pi * (phase - currentFalling) / (1 - currentFalling))) / 2
        let gust = phase < currentFalling ? 0 : sin(.pi * (phase - currentFalling) / (1 - currentFalling))
        // Each breeze blows the other way.
        let sweep: Double = round.isMultiple(of: 2) ? 1 : -1
        let seed = current * 13 + 5
        // One swing every 8 s, carried straight through.
        let swing = sin(2 * .pi * shown / 8 + noise(seed, 4) * 2 * .pi)
        let drift = (noise(seed, 5) - 0.5) * size.width * 0.2 + 0.35 * side * swing + sweep * gust * size.width * 0.22
        // Eased in towards the sides, so no more than a sliver goes past them.
        let reach = size.width / 2 - side * 0.4
        return Cover(
            id: ID(card: -1, round: 0),
            album: current,
            center: CGPoint(
                x: size.width / 2 + reach * tanh(drift / reach),
                y: size.height * mix(0.2, 0.6, depth) + 0.12 * side * (swing * swing - 0.5)
            ),
            side: side, seed: seed, progress: phase,
            turn: (roll: 0.3 * swing + 0.25 * sweep * gust, pitch: 0.3 * (swing * swing - 0.4), yaw: 0.4 * swing * abs(swing))
        )
    }

    /// Seconds into its fall at which the album on show passes `point`'s height.
    private static func featherLead(at point: CGPoint, in size: CGSize) -> Double {
        let depth = min(max((Double(point.y / size.height) - 0.2) / 0.4, 0), 1)
        return currentFalling * acos(1 - 2 * depth) / .pi * currentFall
    }

    // MARK: - Shapes

    /// A fixed 0…1 per seed and salt.
    static func noise(_ seed: Int, _ salt: Int = 0) -> Double {
        let x = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    private static func smootherstep(_ t: Double) -> Double { t * t * t * (t * (6 * t - 15) + 10) }
}

extension ListeningPickFlight {
    /// Seconds that run with the wall clock and ease to a new speed rather than jump.
    struct Clock {
        private var anchor: Date
        private var anchorTime: Double
        private var fromRate = 1.0
        private var toRate = 1.0
        private var ramp = 0.0

        init(at date: Date) {
            anchor = date
            // Folded so the numbers stay small; 3600 s is a whole number of throws and of falls.
            anchorTime = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        }

        func rate(at date: Date) -> Double {
            let t = date.timeIntervalSince(anchor)
            guard ramp > 0, t < ramp else { return toRate }
            return fromRate + (toRate - fromRate) * max(0, t) / ramp
        }

        func time(at date: Date) -> Double {
            let t = max(0, date.timeIntervalSince(anchor))
            let ramped = min(t, ramp)
            let rampedRate = ramp > 0 ? fromRate + (toRate - fromRate) * ramped / ramp : toRate
            return anchorTime + ramped * (fromRate + rampedRate) / 2 + (t - ramped) * toRate
        }

        mutating func ease(to rate: Double, over seconds: Double, at date: Date) {
            anchorTime = time(at: date)
            fromRate = self.rate(at: date)
            toRate = rate
            ramp = seconds
            anchor = date
        }
    }
}
