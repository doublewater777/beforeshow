import SwiftUI
import UIKit

/// 帮我挑一张 as a record shelf: the 3D cabinet, the front-facing rack, the carousel, the toss or the feathers. Drag the row;
/// the album in front comes forward.
struct ListeningPickShelfView: View {
    let style: ListeningPickStyle
    let discs: [ListeningDisc]
    let show: Show
    @Binding var currentID: String?
    let isAuditioning: (ListeningDisc) -> Bool
    let onListen: (ListeningDisc) -> Void

    @State private var position: Double
    @State private var dragStart: Double?
    @State private var ticker = ShelfFrameTicker()
    /// The 3D row swinging in when the shelf opens.
    @State private var entrance: Double = 1
    @State private var entranceTicker = ShelfFrameTicker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPicking = false
    @State private var landing: Int?
    @State private var tone: Color = BSColor.Stage.glowBlue

    init(
        style: ListeningPickStyle, discs: [ListeningDisc], show: Show, currentID: Binding<String?>,
        isAuditioning: @escaping (ListeningDisc) -> Bool, onListen: @escaping (ListeningDisc) -> Void
    ) {
        self.style = style
        self.discs = discs
        self.show = show
        _currentID = currentID
        self.isAuditioning = isAuditioning
        self.onListen = onListen
        // Opens on the current album from the first frame, so the 3D shelf loads the covers round it first.
        _position = State(initialValue: Double(discs.firstIndex { $0.id == currentID.wrappedValue } ?? 0))
    }

    /// The carousel goes round for ever; the shelves stop at their ends.
    private var loops: Bool { style == .ring }
    /// Where the row is within one lap, for the scrubber.
    private var lapPosition: Double { loops ? ListeningPickLoop.wrapped(position, count: discs.count) : position }
    private var index: Int {
        loops ? ListeningPickLoop.index(at: position, count: discs.count) : min(max(Int(position.rounded()), 0), discs.count - 1)
    }
    private var current: ListeningDisc { discs[index] }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ListeningPickShelfStage(
                    style: style, discs: discs, show: show, position: position,
                    landing: landing, entrance: entrance, onReady: playEntrance
                )
                .allowsHitTesting(false)
                Color.clear
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
        .background(ListeningPickShelfBackdrop(tone: tone).ignoresSafeArea())
        .onAppear {
            guard !reduceMotion else { return }
            if style == .shelf3D { entrance = 0 }
            if [.ring, .toss, .feather].contains(style) { runEntrance() }
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
        .onDisappear {
            ticker.stop()
            entranceTicker.stop()
        }
    }

    // MARK: - Chrome

    /// Album info lives in the header row, between close and the style button.
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
            let knobX = gap * (CGFloat(lapPosition) * CGFloat(barsPerDisc) + CGFloat(barsPerDisc) / 2)
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
                        let target = min(max(Double(value.location.x / width) * Double(count) - 0.5, 0), Double(count - 1))
                        position += target - lapPosition
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
            let distance: Double = (Double(bar) + 0.5) / Double(barsPerDisc) - lapPosition - 0.5
            let swell: Double = exp(-distance * distance / 3.2)
            let height = CGFloat(max(3, 30 * (base + 0.55 * swell)))
            let x: CGFloat = gap * CGFloat(bar) + gap / 2 - 0.75
            let rect = CGRect(x: x, y: size.height - height, width: 1.5, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(.white.opacity(0.35 + 0.5 * swell)))
        }
    }

    // MARK: - Motion

    /// Albums travelled for a finger movement, so the row stays under the finger.
    private func albums(for translation: CGSize, in size: CGSize) -> Double {
        let step = ListeningPickShelfStage.rowStep(for: style, count: discs.count, in: size)
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
        let distance = loops ? ListeningPickLoop.turn(from: from, to: target, count: discs.count) : Double(target) - from
        let run = min(abs(distance), 24) * (distance < 0 ? -1 : 1)
        let skip = distance - run
        let duration = 1.1 + abs(run) * 0.02
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
        runEntrance()
    }

    private func runEntrance() {
        let duration = ListeningPickShelfStage.openingDuration(for: style)
        entrance = 0
        entranceTicker.start { elapsed in
            entrance = min(1, elapsed / duration)
            return entrance < 1
        }
    }

    private func clamp(_ value: Double) -> Double { loops ? value : min(max(value, 0), Double(discs.count - 1)) }
}

/// Steps an animation once per screen refresh; the step returns false when it is done.
@MainActor
private final class ShelfFrameTicker: NSObject {
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var elapsed: Double = 0
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
        lastTime = nil
        elapsed = 0
        step = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        // A stalled frame (RealityKit warming up its first render) holds the animation instead of skipping ahead.
        elapsed += min(now - (lastTime ?? now), 1.0 / 20)
        lastTime = now
        if step?(elapsed) != true { stop() }
    }
}
