import SwiftUI

/// What plays on its own behind 冲天抛洒 and 飘羽: covers thrown up from a spout below the screen, or falling like
/// feathers at three depths. Every card is a function of the clock, so nothing has to drive it.
struct ListeningPickFlightField: View {
    let style: ListeningPickStyle
    let discs: [ListeningDisc]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                // Folded so the numbers stay small; 3600 s is a whole number of throws and of falls.
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                if !discs.isEmpty {
                    if style == .toss {
                        toss(at: time, in: proxy.size)
                    } else {
                        feathers(at: time, in: proxy.size)
                    }
                }
            }
            // Clear of the album title in the header.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0.02), .init(color: .black, location: 0.14)], startPoint: .top, endPoint: .bottom))
        }
    }

    /// A fixed 0…1 per seed and salt.
    static func noise(_ seed: Int, _ salt: Int = 0) -> Double {
        let x = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private static func axis(_ seed: Int, _ salt: Int) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let v = (noise(seed, salt) * 2 - 1, noise(seed, salt + 1) * 2 - 1, noise(seed, salt + 2) * 2 - 1)
        let length = max((v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot(), 0.001)
        return (v.0 / length, v.1 / length, v.2 / length)
    }

    private func cover(_ index: Int, side: CGFloat) -> some View {
        let disc = discs[index % discs.count]
        return ListeningArtwork(url: disc.artworkURL, title: disc.title)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.04, style: .continuous))
    }

    // MARK: - Toss

    private static let tossCards = 24
    /// Seconds from the spout to falling out of sight.
    private static let tossFlight = 4.5

    private func toss(at time: Double, in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<Self.tossCards, id: \.self) { card in
                thrown(card, at: time, in: size)
            }
        }
    }

    /// Up a parabola from just below the screen to its peak, then down past where it started; each throw is new.
    private func thrown(_ card: Int, at time: Double, in size: CGSize) -> some View {
        let count = Self.tossCards
        let base = min(size.height * 0.075, size.width * 0.16)
        let flight = time / Self.tossFlight + (Double(card) + 0.6 * Self.noise(card, 3)) / Double(count)
        let throwIndex = Int(flight.rounded(.down))
        let tau = flight - Double(throwIndex)
        let seed = card * 7 + throwIndex * 131
        let spout = size.height + base * 0.3
        let peak = size.height * Self.mix(0.5, 0.88, Self.noise(seed, 1).squareRoot()) + base * 0.3
        let drop = base * 1.2
        let launch = 2 * peak + 2 * (peak * peak + peak * drop).squareRoot()
        let fall = launch + drop
        let spread = Self.noise(seed, 2) * 2 - 1
        let drift = (spread < 0 ? -1 : 1) * pow(abs(spread), 0.8) * size.width * 0.56
        let depth = 1 / (1 - 0.08 * Self.mix(-2.4, 1, Self.noise(seed, 4)) * tau)
        let grown = 1 - pow(1 - min(1, tau / 0.38), 3)
        let side = Self.mix(0.85, 1.12, Self.noise(seed, 30)) * Self.mix(0.38, 1, grown) * base * depth
        let tumble = 0.8 * 2 * .pi * tau * Self.mix(0.45, 1, Self.noise(seed, 22))
        return cover(card + throwIndex * count, side: side)
            .rotation3DEffect(.radians(tumble), axis: Self.axis(seed, 20), perspective: 0.4)
            .rotation3DEffect(.radians((Self.noise(seed, 12) - 0.5) * 1.1), axis: Self.axis(seed, 10), perspective: 0.4)
            .position(
                x: size.width / 2 + (Self.noise(seed, 5) - 0.5) * 0.25 * base + drift * pow(tau, 0.8),
                y: spout - (launch * tau - fall * tau * tau)
            )
    }

    // MARK: - Feathers

    private static let featherCards = 18
    /// One loop; near feathers fall three times in it, middle ones twice, far ones once.
    private static let featherLoop = 16.0

    /// Far, middle and near, each blurred once as a whole rather than card by card.
    private static let featherLayers: [(lower: Double, upper: Double, blur: CGFloat)] = [(0, 0.36, 2.5), (0.36, 0.72, 1), (0.72, 1, 0)]

    private func feathers(at time: Double, in size: CGSize) -> some View {
        let cards = (0..<Self.featherCards).map { (card: $0, near: Self.nearness($0)) }
        return ZStack {
            ForEach(Self.featherLayers.indices, id: \.self) { layer in
                let depth = Self.featherLayers[layer]
                ZStack {
                    ForEach(cards.filter { depth.lower <= $0.near && $0.near < depth.upper }, id: \.card) { item in
                        falling(item.card, near: item.near, at: time, in: size)
                    }
                }
                .blur(radius: depth.blur)
            }
        }
    }

    /// 0 for the farthest layer, nearly 1 for the nearest.
    private static func nearness(_ card: Int) -> Double {
        let x = Double(card) * 0.4142 + 0.17 + 0.25 * noise(card, 1)
        return x - x.rounded(.down)
    }

    /// Falls the screen while swinging side to side, quickest through the middle of a swing and tipping up at its ends.
    private func falling(_ card: Int, near: Double, at time: Double, in size: CGSize) -> some View {
        let falls: Double = near > 0.72 ? 3 : near > 0.36 ? 2 : 1
        let side = Self.mix(0.85, 1.05, Self.noise(card, 2)) * min(size.height * 0.16, size.width * 0.34) * Self.mix(0.55, 1, near)
        let phase = Double(card) * 0.618034 + 0.31 * Self.noise(card, 3)
        let fallen = (time / Self.featherLoop * falls + phase).truncatingRemainder(dividingBy: 1)
        let margin = side * 0.9 + 10
        let swings: Double = falls == 3 ? Double(1 + card % 2) : Double(1 + card % 3)
        let offset = Self.noise(card, 4) * 2 * .pi
        let angle = 2 * .pi * swings * fallen + offset
        let swing = sin(angle)
        let lane = Double(card) * 0.7548 + 0.11
        let x = size.width / 2 + (lane - lane.rounded(.down) - 0.5) * size.width * 0.85 + 0.58 * side * swing
        let y = -margin + fallen * (size.height + 2 * margin) + 0.15 * side * (swing * swing - 0.5)
        let pitch = 0.45 * (swing * swing - 0.4) + 0.12 * sin(2 * angle + offset + 0.5 * cos(angle)) - 0.12
        return cover(card, side: side)
            .rotationEffect(.radians(0.42 * swing))
            .rotation3DEffect(.radians(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.radians(0.6 * swing * abs(swing)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .brightness(-0.18 * (1 - near))
            .position(x: x, y: y)
    }
}
