import SwiftUI

/// Draws 冲天抛洒 and 飘羽 from `ListeningPickFlight`: the covers in flight, the album on show above them, and a held
/// cover lifted on top. As the field stops under a finger, every cover turns to face you.
struct ListeningPickFlightField: View {
    private typealias Flight = ListeningPickFlight
    private typealias Cover = ListeningPickFlight.Cover

    let discs: [ListeningDisc]
    /// The album on show.
    let current: Int
    let flight: ListeningPickFlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { context in
                if !discs.isEmpty {
                    field(Flight.Layout(albums: discs.count, current: current, size: proxy.size, isStill: reduceMotion), at: context.date)
                }
            }
            // Clear of the album title in the header.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0.02), .init(color: .black, location: 0.14)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func field(_ layout: Flight.Layout, at date: Date) -> some View {
        let time = flight.time(at: date, in: layout)
        let facing = reduceMotion ? 0 : flight.facing(at: date)
        let lifting = flight.lifting(at: date, isStill: reduceMotion)
        let covers = flight.covers(in: layout, time: time).map { cover in
            var cover = cover
            cover.facing = max(cover.facing, facing)
            return cover
        }
        let flying = covers.filter { flight.held != .cover($0.id) }
        let held = covers.first { flight.held == .cover($0.id) }.map { cover in
            var cover = cover
            cover.side *= 1 + Flight.lift * lifting
            cover.facing = max(cover.facing, lifting)
            cover.near = 1
            return cover
        }
        var onShow = flight.onShow(in: layout, time: time)
        onShow.facing = max(onShow.facing, facing)
        if flight.held == .onShow {
            onShow.side *= 1 + Flight.lift * 0.4 * lifting
            onShow.facing = max(onShow.facing, lifting)
        }
        return ZStack {
            if flight.style == .toss {
                ForEach(flying, id: \.id) { tumbling($0) }
                thrownOnShow(onShow)
            } else {
                ForEach(Flight.featherLayers.indices, id: \.self) { layer in
                    let depth = Flight.featherLayers[layer]
                    ZStack {
                        ForEach(flying.filter { depth.lower <= $0.near && $0.near < depth.upper }, id: \.id) { feather($0) }
                    }
                    // Sharpens as the field stops, so the far covers can be read too.
                    .blur(radius: depth.blur * (1 - facing))
                }
                fallingOnShow(onShow)
            }
            if let held {
                Group {
                    if flight.style == .toss { tumbling(held) } else { feather(held) }
                }
                .shadow(color: .black.opacity(0.3 * lifting), radius: 14 * lifting, y: 10 * lifting)
            }
        }
    }

    private func artwork(_ album: Int, side: CGFloat) -> some View {
        let disc = discs[album % discs.count]
        return ListeningArtwork(url: disc.artworkURL, title: disc.title)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.04, style: .continuous))
    }

    private static func axis(_ seed: Int, _ salt: Int) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let v = (Flight.noise(seed, salt) * 2 - 1, Flight.noise(seed, salt + 1) * 2 - 1, Flight.noise(seed, salt + 2) * 2 - 1)
        let length = max((v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot(), 0.001)
        return (v.0 / length, v.1 / length, v.2 / length)
    }

    // MARK: - Toss

    /// Tumbling end over end; turning to face you, it goes the short way round.
    private func tumbling(_ cover: Cover) -> some View {
        let tumble = 0.8 * 2 * .pi * cover.progress * Flight.mix(0.45, 1, Flight.noise(cover.seed, 22))
        let faced = (tumble / (2 * .pi)).rounded() * 2 * .pi
        return artwork(cover.album, side: cover.side)
            .rotation3DEffect(.radians(tumble + (faced - tumble) * cover.facing), axis: Self.axis(cover.seed, 20), perspective: 0.4)
            .rotation3DEffect(.radians((Flight.noise(cover.seed, 12) - 0.5) * 1.1 * (1 - cover.facing)), axis: Self.axis(cover.seed, 10), perspective: 0.4)
            .position(cover.center)
    }

    private func thrownOnShow(_ cover: Cover) -> some View {
        let tilt = 1 - cover.facing
        return artwork(cover.album, side: cover.side)
            .rotation3DEffect(.degrees(22 * sin(cover.progress * 2 * .pi) * tilt), axis: (x: 1, y: 0.4 * cover.sway, z: 0), perspective: 0.4)
            .rotationEffect(.degrees(cover.sway * 24 * (cover.progress - 0.3) * tilt))
            .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
            .position(cover.center)
            .opacity(cover.opacity)
    }

    // MARK: - Feathers

    private func turned(_ cover: Cover) -> some View {
        let tilt = 1 - cover.facing
        return artwork(cover.album, side: cover.side)
            .rotationEffect(.radians(cover.turn.roll * tilt))
            .rotation3DEffect(.radians(cover.turn.pitch * tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.radians(cover.turn.yaw * tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }

    private func feather(_ cover: Cover) -> some View {
        turned(cover)
            .brightness(-0.08 * (1 - cover.near))
            .position(cover.center)
    }

    private func fallingOnShow(_ cover: Cover) -> some View {
        turned(cover)
            .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
            .position(cover.center)
            .opacity(cover.opacity)
    }
}
