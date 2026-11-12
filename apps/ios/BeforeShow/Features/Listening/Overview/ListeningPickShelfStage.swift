import SwiftUI

/// What a shelf style draws for a row position, without gestures or chrome; the shelf view and the style previews share it.
struct ListeningPickShelfStage: View {
    let style: ListeningPickStyle
    let discs: [ListeningDisc]
    let show: Show
    let position: Double
    /// Where a pick will land; the 3D shelf starts loading its cases early.
    var landing: Int?
    /// 0 → 1 while the shelf opens.
    var entrance: Double = 1
    var onReady: () -> Void = {}

    /// Bumped as spine colours arrive, so the rack redraws with them.
    @State private var tonesLoaded = 0

    private var index: Int { min(max(Int(position.rounded()), 0), discs.count - 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if style == .shelf3D, #available(iOS 18.0, *) {
                    ListeningPickShelf3D(discs: discs, position: position, landing: landing, entrance: entrance, onReady: onReady)
                }
                drawn(in: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 0.8)], startPoint: .top, endPoint: .bottom))
            }
        }
        .task(id: discs.map(\.id)) {
            // Only the rack prints spines from the drawn side; the 3D shelf prints its own.
            guard style == .rack else { return }
            for disc in discs {
                guard let url = disc.artworkURL, ListeningArtworkTone.cached(url) == nil else { continue }
                _ = await ListeningArtworkTone.tone(for: url)
                tonesLoaded += 1
            }
        }
    }

    /// How long a shelf takes to open: the 3D row swings in, holds and pulls its case out; the ring only turns into place.
    static func openingDuration(for style: ListeningPickStyle) -> Double { style == .shelf3D ? 1.4 : 1.1 }

    /// The on-screen step from one album to the next one back.
    static func rowStep(for style: ListeningPickStyle, count: Int, in size: CGSize) -> CGVector {
        switch style {
        case .shelf3D:
            if #available(iOS 18.0, *) { return ShelfScene3D.screenStep(in: size) }
            return CGVector(dx: rackSide(in: size) * 0.13, dy: 0)
        case .ring:
            let slots = RingLayout.slots(for: count)
            return CGVector(dx: RingLayout(size: size, slots: slots).radius * 2 * .pi / Double(slots), dy: 0)
        case .rack, .feed:
            return CGVector(dx: rackSide(in: size) * 0.13, dy: 0)
        // Nothing follows the finger here: a swipe up throws the next album, a swipe down lets it fall.
        case .toss:
            return CGVector(dx: 0, dy: size.height * 0.25)
        case .feather:
            return CGVector(dx: 0, dy: -size.height * 0.25)
        }
    }

    @ViewBuilder
    private func drawn(in size: CGSize) -> some View {
        if !discs.isEmpty {
            switch style {
            case .rack: rack(in: size).id(tonesLoaded)
            case .ring: carousel(in: size)
            case .toss, .feather: ListeningPickFlightField(style: style, discs: discs, current: index)
            case .shelf3D, .feed: EmptyView()
            }
        }
    }

    private func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    // MARK: - Rack

    /// The rack's cover size: phone-sized on a phone, growing with the height on iPad.
    private static func rackSide(in size: CGSize) -> CGFloat {
        min(size.width * 0.5, max(200, min(size.height * 0.26, 300)))
    }

    private func rack(in size: CGSize) -> some View {
        let side = Self.rackSide(in: size)
        // Enough spines on each side to reach the screen edges.
        let reach = Int((size.width / 2 / (side * 0.065)).rounded(.up)) + 2
        let lower = max(0, index - reach)
        let upper = min(discs.count - 1, index + reach)
        return ZStack {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1.5)
                .position(x: size.width / 2, y: size.height * 0.62 + side / 2 + 6)
            ForEach(lower...upper, id: \.self) { itemIndex in
                rackItem(discs[itemIndex], offset: Double(itemIndex) - position, side: side, in: size)
            }
        }
    }

    private func rackItem(_ disc: ListeningDisc, offset d: Double, side: CGFloat, in size: CGSize) -> some View {
        let pop = smoothstep(max(0, 1 - abs(d)))
        let flank = min(max(d, -1), 1)
        return ShelfJewelCase(disc: disc, show: show, side: side)
            .scaleEffect(0.86 + 0.2 * pop)
            .rotation3DEffect(.degrees(-80 * flank), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .shadow(color: .black.opacity(0.2 + 0.3 * pop), radius: 4 + 16 * pop, y: 6 + 12 * pop)
            .position(x: size.width / 2 + d * side * 0.065 + flank * side * 0.58, y: size.height * 0.62 - side * 0.5 * pop)
            .zIndex(-abs(d) * 10)
    }

    // MARK: - Carousel

    /// Covers standing round a wide, flat ring seen from above, always facing you; the one in front is current.
    private func carousel(in size: CGSize) -> some View {
        let slots = RingLayout.slots(for: discs.count)
        let ring = RingLayout(size: size, slots: slots)
        let arrival = 1 - pow(1 - entrance, 3)
        // Opens with the ring swinging round into place.
        let turn = position - (1 - arrival) * Double(slots) * 0.5
        return ZStack {
            if discs.count <= slots {
                // Few albums go all the way round, end to end.
                ForEach(discs.indices, id: \.self) { itemIndex in
                    ringItem(discs[itemIndex], offset: remainder(Double(itemIndex) - turn, Double(slots)), slots: slots, fades: false, ring: ring)
                }
            } else {
                // More albums than slots go round in turn: half a slot past each side, so the album leaving
                // at the back cross-fades with the one arriving.
                let half = Double(slots) / 2 + 0.5
                let lower = Int((turn - half).rounded(.up))
                let upper = Int((turn + half).rounded(.down))
                ForEach(lower...upper, id: \.self) { step in
                    ringItem(discs[ListeningPickLoop.index(at: Double(step), count: discs.count)],
                             offset: Double(step) - turn, slots: slots, fades: true, ring: ring)
                }
            }
        }
        .scaleEffect(0.85 + 0.15 * arrival)
        .opacity(min(1, entrance * 2.5))
    }

    private func ringItem(_ disc: ListeningDisc, offset d: Double, slots: Int, fades: Bool, ring: RingLayout) -> some View {
        let angle = d * 2 * .pi / Double(slots)
        let depth = cos(angle)
        let scale = (1 - RingLayout.perspective) / (1 - RingLayout.perspective * depth)
        let pop = smoothstep(max(0, 1 - abs(d)))
        let fade = fades ? smoothstep(min(1, max(0, Double(slots) / 2 + 0.5 - abs(d)))) : 1
        return flatCover(disc, side: ring.side)
            .brightness(-0.14 * (1 - depth) / 2)
            .shadow(color: .black.opacity(0.18 + 0.22 * pop), radius: 6 + 12 * pop, y: 4 + 8 * pop)
            .scaleEffect(scale * (1 + 0.12 * pop))
            .position(
                x: ring.centre.x + ring.radius * sin(angle) * scale,
                y: ring.centre.y + ring.depth * depth * scale - ring.side * 0.12 * pop
            )
            .opacity(fade)
            .zIndex(depth * 100 + pop)
    }

    private func flatCover(_ disc: ListeningDisc, side: CGFloat) -> some View {
        ListeningArtwork(url: disc.artworkURL, title: disc.title)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

/// The shelves' light haze, tinted by the album on show.
struct ListeningPickShelfBackdrop: View {
    var tone: Color = BSColor.Stage.glowBlue

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.66, green: 0.62, blue: 0.74), Color(red: 0.62, green: 0.56, blue: 0.6), Color(red: 0.34, green: 0.3, blue: 0.38)], startPoint: .top, endPoint: .bottom)
            LinearGradient(
                colors: [tone.opacity(0.4), tone.opacity(0.25), BSColor.Stage.background.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [.white.opacity(0.10), .clear], center: .init(x: 0.6, y: 0.45), startRadius: 0, endRadius: 320)
        }
    }
}

/// The carousel's ring on screen: wide enough that the side covers run off the edges, flattened by the view from above.
private struct RingLayout {
    /// Albums round the ring at once; fewer albums than this make a smaller ring of their own.
    static func slots(for count: Int) -> Int { min(max(count, 1), 16) }
    /// How much smaller the back of the ring is than the front.
    static let perspective = 0.13

    let side: CGFloat
    let radius: CGFloat
    let depth: CGFloat
    let centre: CGPoint

    init(size: CGSize, slots: Int) {
        side = min(size.width * 0.26, size.height * 0.14, 200)
        // A small ring keeps its covers side by side instead of spreading a few round the full circle.
        radius = min(size.width * 0.5, side * 2.6, side * 1.3 * Double(slots) / (2 * .pi))
        depth = min(radius * 0.85, size.height * 0.22)
        centre = CGPoint(x: size.width / 2, y: size.height * 0.4)
    }
}

/// A CD case seen face on: cover in the tray, printed spine band and hinge.
private struct ShelfJewelCase: View {
    let disc: ListeningDisc
    let show: Show
    let side: CGFloat

    static let frame = Color(red: 0.86, green: 0.85, blue: 0.91)
    static let edgeLight = Color(red: 0.96, green: 0.95, blue: 0.99)
    static let edgeDark = Color(red: 0.58, green: 0.56, blue: 0.66)

    private var spineColor: Color {
        guard let tone = ListeningArtworkTone.cached(disc.artworkURL) else { return Color(white: 0.12) }
        return Color(uiColor: ListeningArtworkTone.spine(for: tone).fill)
    }

    private var spineInk: Color {
        guard let tone = ListeningArtworkTone.cached(disc.artworkURL), ListeningArtworkTone.spine(for: tone).isLight else { return .white }
        return .black.opacity(0.8)
    }

    private var year: String? {
        disc.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
    }

    var body: some View {
        let hinge = side * 0.055
        let band = side * 0.15
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Self.frame)
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(disc.title)
                        .font(.system(size: max(8, side * 0.062), weight: .heavy))
                        .tracking(1)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .frame(width: side * 0.7, alignment: .center)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: band, height: side * 0.72)
                    if let year {
                        Text(verbatim: year).font(.system(size: max(6, side * 0.04), weight: .bold))
                    }
                }
                .foregroundStyle(spineInk)
                .frame(width: band, height: side * 0.92)
                .background(spineColor)
                ListeningArtwork(url: disc.artworkURL, title: disc.title)
                    .frame(width: side * 0.92 - band, height: side * 0.92)
                    .clipped()
            }
            .offset(x: hinge + side * 0.01, y: side * 0.04)
            Rectangle()
                .fill(Self.edgeLight)
                .frame(width: hinge, height: side)
                .overlay(alignment: .trailing) { Rectangle().fill(Self.edgeDark.opacity(0.6)).frame(width: 0.5) }
            LinearGradient(colors: [.white.opacity(0.14), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 0.8)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

