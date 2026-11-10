import SwiftUI
import UIKit


/// 帮我挑一张 as a record shelf: the 3D cabinet or the front-facing rack. Drag the row; the album in front slides out.
struct ListeningPickShelfView: View {
    let style: ListeningPickStyle
    let discs: [ListeningDisc]
    let show: Show
    @Binding var currentID: String?
    let isAuditioning: (ListeningDisc) -> Bool
    let onListen: (ListeningDisc) -> Void

    @State private var position: Double = 0
    @State private var dragStart: Double?
    @State private var ticker = ShelfFrameTicker()
    /// The 3D row arriving from its far end when the shelf opens.
    @State private var entrance: Double = 1
    @State private var entranceTicker = ShelfFrameTicker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPicking = false
    @State private var landing: Int?
    @State private var tone: Color = BSColor.Stage.glowBlue
    /// Bumped as spine colours arrive, so cases redraw with them.
    @State private var tonesLoaded = 0

    private var index: Int { min(max(Int(position.rounded()), 0), discs.count - 1) }
    private var current: ListeningDisc { discs[index] }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if style == .shelf3D, #available(iOS 18.0, *) {
                    ListeningPickShelf3D(discs: discs, position: position, landing: landing, entrance: entrance, onReady: playEntrance)
                        .allowsHitTesting(false)
                }
                shelf(in: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 0.8)], startPoint: .top, endPoint: .bottom))
                    .contentShape(Rectangle())
                    .gesture(drag(in: proxy.size))
                VStack(spacing: 0) {
                    titleBlock
                    Spacer()
                    scrubber
                        .padding(.horizontal, BSSpacing.xl)
                        .padding(.bottom, BSSpacing.md)
                    controls
                }
                .padding(.bottom, BSSpacing.md)
            }
        }
        .background(backdrop)
        .onAppear {
            position = Double(discs.firstIndex { $0.id == currentID } ?? 0)
            if style == .shelf3D, !reduceMotion { entrance = 0 }
        }
        .onChange(of: discs.map(\.id)) { _, _ in
            ticker.stop()
            position = Double(discs.firstIndex { $0.id == currentID } ?? 0)
        }
        .onChange(of: index) { _, newIndex in currentID = discs[newIndex].id }
        .sensoryFeedback(.selection, trigger: index)
        .task(id: current.artworkURL) {
            guard let url = current.artworkURL, let color = await ListeningArtworkTone.tone(for: url) else { return }
            withAnimation(.easeInOut(duration: 0.7)) { tone = Color(uiColor: color) }
        }
        .task(id: discs.map(\.id)) {
            // The 3D shelf prints its own spines; only the drawn shelves need every tone up front.
            guard style != .shelf3D else { return }
            for disc in discs {
                guard let url = disc.artworkURL, ListeningArtworkTone.cached(url) == nil else { continue }
                _ = await ListeningArtworkTone.tone(for: url)
                tonesLoaded += 1
            }
        }
        .onDisappear {
            ticker.stop()
            entranceTicker.stop()
        }
    }

    // MARK: - Backdrop and chrome

    private var backdrop: some View {
        ZStack {
            // Light, airy haze like the reference, tinted by the album on show.
            LinearGradient(colors: [Color(red: 0.66, green: 0.62, blue: 0.74), Color(red: 0.62, green: 0.56, blue: 0.6), Color(red: 0.34, green: 0.3, blue: 0.38)], startPoint: .top, endPoint: .bottom)
            LinearGradient(
                colors: [tone.opacity(0.4), tone.opacity(0.25), BSColor.Stage.background.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [.white.opacity(0.10), .clear], center: .init(x: 0.6, y: 0.45), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }

    /// Album info lives in the header row, between close and filter.
    private var titleBlock: some View {
        VStack(spacing: 2) {
            Text(current.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                if isPicking {
                    Image(systemName: "sparkles")
                } else if isAuditioning(current) {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                }
                Text(verbatim: "\(current.displayArtistName(for: show)) · \(ListeningReleaseMeta.yearAndTrackCount(current))")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(BSColor.Stage.foreground.opacity(0.7))
        }
        .frame(height: BSLayout.minTouchTarget)
        .blur(radius: isPicking ? 5 : 0)
        .padding(.horizontal, BSLayout.minTouchTarget + BSSpacing.md)
        .animation(.easeOut(duration: 0.2), value: isPicking)
    }

    private var controls: some View {
        HStack(spacing: BSSpacing.md) {
            Button(action: pick) {
                Label(ListeningCopy.text("帮我挑一张"), systemImage: "shuffle")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(BSColor.Stage.background)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Capsule().fill(BSColor.Stage.foreground))
            }
            .disabled(isPicking || discs.count < 2)
            Button { onListen(current) } label: {
                Image(systemName: "headphones")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.white.opacity(0.14)))
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))
            }
            .accessibilityLabel(ListeningCopy.text("就听这张"))
            .disabled(isPicking)
        }
        .buttonStyle(.plain)
    }

    /// One bar per album, height from its track count; the bars swell around where you are.
    private var scrubber: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let count = discs.count
            let barsPerDisc = max(1, min(6, 72 / max(count, 1)))
            let total = count * barsPerDisc
            let gap = width / CGFloat(max(total, 1))
            let maxTracks = Double(discs.map(\.tracks.count).max() ?? 1)
            let knobX = gap * (CGFloat(position) * CGFloat(barsPerDisc) + CGFloat(barsPerDisc) / 2)
            ZStack(alignment: .bottomLeading) {
                // One canvas instead of a view per bar: this redraws every frame while the shelf moves.
                Canvas { context, canvas in
                    drawBars(in: &context, size: canvas, total: total, barsPerDisc: barsPerDisc, gap: gap, maxTracks: maxTracks)
                }
                Rectangle().fill(.white).frame(width: 1.5, height: 40).offset(x: knobX - 0.75)
                Circle().fill(.white).frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.8), radius: 4)
                    .offset(x: knobX - 4, y: -38)
            }
            .frame(width: width, height: proxy.size.height, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPicking else { return }
                        ticker.stop()
                        position = clamp(Double(value.location.x / width) * Double(count) - 0.5)
                    }
                    .onEnded { _ in glide(velocity: 0) }
            )
        }
        .frame(height: 48)
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize, total: Int, barsPerDisc: Int, gap: CGFloat, maxTracks: Double) {
        for bar in 0..<total {
            let disc = discs[bar / barsPerDisc]
            let wobble = Double((bar * 7919 + disc.id.count * 31) % 9) / 9
            let base: Double = 0.18 + 0.32 * Double(disc.tracks.count) / max(maxTracks, 1) + 0.12 * wobble
            let distance: Double = (Double(bar) + 0.5) / Double(barsPerDisc) - position - 0.5
            let swell: Double = exp(-distance * distance / 3.2)
            let height = CGFloat(max(3, 30 * (base + 0.55 * swell)))
            let x: CGFloat = gap * CGFloat(bar) + gap / 2 - 0.75
            let rect = CGRect(x: x, y: size.height - height, width: 1.5, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(.white.opacity(0.35 + 0.5 * swell)))
        }
    }

    // MARK: - Shelf

    private func shelf(in size: CGSize) -> some View {
        let lower = max(0, index - 10)
        let upper = min(discs.count - 1, index + 22)
        let side = min(size.width * 0.5, 200)
        return ZStack {
            if style == .rack {
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(height: 1.5)
                    .position(x: size.width / 2, y: size.height * 0.62 + side / 2 + 6)
            }
            if style == .rack {
                ForEach(Array(discs[lower...upper].enumerated()), id: \.element.id) { offset, disc in
                    item(disc, at: lower + offset, side: side, in: size)
                }
            }
        }
        .id(tonesLoaded)
    }

    @ViewBuilder
    private func item(_ disc: ListeningDisc, at itemIndex: Int, side: CGFloat, in size: CGSize) -> some View {
        let d = Double(itemIndex) - position
        let pop = smoothstep(max(0, 1 - abs(d)))
        if style == .rack {
            let flank = min(max(d, -1), 1)
            ShelfJewelCase(disc: disc, show: show, side: side)
                .scaleEffect(0.86 + 0.2 * pop)
                .rotation3DEffect(.degrees(-80 * flank), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                .shadow(color: .black.opacity(0.2 + 0.3 * pop), radius: 4 + 16 * pop, y: 6 + 12 * pop)
                .position(x: size.width / 2 + d * 13 + flank * side * 0.58, y: size.height * 0.62 - side * 0.5 * pop)
                .zIndex(-abs(d) * 10)
        }
    }

    private func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    // MARK: - Motion

    /// The on-screen step from one album to the next one back, and its length.
    private func rowStep(in size: CGSize) -> CGVector {
        if style == .shelf3D, #available(iOS 18.0, *) {
            return ShelfScene3D.screenStep(in: size)
        }
        return CGVector(dx: 26, dy: 0)
    }

    /// Albums travelled for a finger movement, so the row stays under the finger.
    private func albums(for translation: CGSize, in size: CGSize) -> Double {
        let step = rowStep(in: size)
        return -(translation.width * step.dx + translation.height * step.dy) / (step.dx * step.dx + step.dy * step.dy)
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isPicking else { return }
                if dragStart == nil {
                    ticker.stop()
                    dragStart = position
                }
                position = clamp((dragStart ?? position) + albums(for: value.translation, in: size))
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                dragStart = nil
                glide(velocity: albums(for: CGSize(width: value.velocity.width, height: value.velocity.height), in: size))
            }
    }

    /// Carries on at the release speed and slows into the nearest album, like a paging scroll view.
    private func glide(velocity: Double) {
        let decay = 6.0
        let from = position
        let target = clamp((from + velocity / decay).rounded())
        ticker.start { elapsed in
            let remaining = (target - from) * exp(-decay * elapsed)
            position = target - remaining
            if abs(remaining) < 0.002 {
                position = target
                return false
            }
            return true
        }
    }

    private func pick() {
        let others = discs.filter { $0.id != current.id }
        guard let chosen = ListeningDiscPickPolicy.pick(
            showID: show.id, scopeKey: ListeningDiscPickPolicy.showScopeKey,
            candidates: others, lineupNames: show.artistNames
        ), let target = discs.firstIndex(where: { $0.id == chosen.id }) else { return }
        isPicking = true
        landing = target
        // Shows at most a couple of dozen albums going by; the rest is skipped mid-run, while the row is still fast
        // and the landing covers have had time to load.
        let from = position
        let distance = Double(target) - from
        let run = min(abs(distance), 24) * (distance < 0 ? -1 : 1)
        let skip = distance - run
        let duration = 1.6 + abs(run) * 0.03
        ticker.start { elapsed in
            let t = min(1, elapsed / duration)
            let eased = 1 - pow(1 - t, 3)
            position = from + (eased > 0.7 ? skip : 0) + run * eased
            if t < 1 { return true }
            isPicking = false
            landing = nil
            return false
        }
    }

    private func playEntrance() {
        guard entrance == 0 else { return }
        entranceTicker.start { elapsed in
            entrance = min(1, elapsed / 1.6)
            return entrance < 1
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), Double(discs.count - 1)) }
}

/// Steps an animation once per screen refresh; the step returns false when it is done.
@MainActor
private final class ShelfFrameTicker: NSObject {
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval?
    private var step: ((Double) -> Bool)?

    func start(_ step: @escaping (Double) -> Bool) {
        stop()
        self.step = step
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        startTime = nil
        step = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let elapsed = now - (startTime ?? now)
        if startTime == nil { startTime = now }
        if step?(elapsed) != true { stop() }
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

