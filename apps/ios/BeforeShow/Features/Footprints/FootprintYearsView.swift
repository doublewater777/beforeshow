import SwiftUI

/// 这些年 as a gallery corridor: every show's cover hung down both walls, the newest nearest and older ones further
/// down, lost in the haze. The corridor walks itself back through the years, the card below following the cover you
/// pass; a swipe takes over until you let go.
struct FootprintYearsView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    /// Each year's line under the header, worked out once rather than every walking frame.
    private let yearSummaries: [Int: String]

    init(archive: FootprintArchiveSnapshot, covers: [UUID: FootprintCover]) {
        self.archive = archive
        self.covers = covers
        yearSummaries = Dictionary(uniqueKeysWithValues: archive.allYearActivities.map {
            ($0.year, Self.summaryText(showCount: $0.totalShows, durationMinutes: $0.totalDurationMinutes))
        })
    }

    static func summaryText(showCount: Int, durationMinutes: Int) -> String {
        let count = BSLocalization.format("%lld 场", showCount)
        guard durationMinutes > 0 else { return count }
        let duration = durationMinutes < 60
            ? ShowDurationFormatter.single(totalMinutes: durationMinutes)
            : ShowDurationFormatter.aggregate(totalMinutes: durationMinutes)
        return "\(count) · \(duration)"
    }

    /// How far down the corridor you stand, in covers. Fractional while walking.
    @State private var resting: Double = 0
    /// A quick eased walk: a swipe's landing or a jump to a tapped cover.
    @State private var walk: (from: Double, start: Date, duration: Double)?
    /// Walking on by itself towards the oldest show.
    @State private var stroll: FootprintYearsWalk?
    @State private var dragPosition: Double?
    @State private var dragStart: Double?
    @State private var hasAppeared = false
    @State private var detailTarget: FootprintDetailDestination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shows: [Show] { archive.shows }
    /// Finger travel for one cover.
    private let stepHeight: CGFloat = 110

    var body: some View {
        TimelineView(.animation(paused: walk == nil && stroll == nil && dragPosition == nil)) { context in
            let position = position(at: context.date)
            let current = currentShow(at: position)
            ZStack(alignment: .bottom) {
                Color.clear.contentShape(Rectangle())
                FootprintGalleryHall(shows: shows, covers: covers, position: position, selectedID: current?.id) { show in
                    if show.id == current?.id {
                        detailTarget = FootprintDetailDestination(show: show)
                    } else if let index = shows.firstIndex(where: { $0.id == show.id }) {
                        walk(to: Double(index), from: position)
                    }
                }
                header(position: position)
                if let current {
                    infoCard(current)
                        .id(current.id)
                        .transition(.opacity)
                        .padding(.horizontal, BSSpacing.roomy)
                        .padding(.bottom, BSSpacing.md)
                }
            }
            .animation(.easeOut(duration: 0.25), value: current?.id)
        }
        .gesture(drag)
        .background(ListeningPickShelfBackdrop().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("这些年")) } }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.selection, trigger: Int(resting.rounded()))
        .onAppear {
            guard !hasAppeared else { return startStroll() }
            hasAppeared = true
            // Opens walking in from the corridor's mouth.
            startStroll(lead: reduceMotion ? 0 : FootprintYearsWalk.openingLead)
        }
        .onDisappear {
            resting = position(at: .now)
            walk = nil
            stroll = nil
        }
        .task(id: walk?.start) {
            guard let walk else { return }
            try? await Task.sleep(for: .seconds(walk.duration))
            guard !Task.isCancelled else { return }
            self.walk = nil
            startStroll()
        }
        .task(id: stroll?.start) {
            guard let stroll else { return }
            try? await Task.sleep(for: .seconds(stroll.duration))
            guard !Task.isCancelled else { return }
            resting = lastIndex
            self.stroll = nil
        }
    }

    // MARK: - Walking

    private var lastIndex: Double { Double(max(shows.count - 1, 0)) }

    private func currentShow(at position: Double) -> Show? {
        let index = min(max(Int(position.rounded()), 0), shows.count - 1)
        return shows.indices.contains(index) ? shows[index] : nil
    }

    private func position(at date: Date) -> Double {
        if let dragPosition { return dragPosition }
        if let walk {
            let t = min(1, date.timeIntervalSince(walk.start) / walk.duration)
            let eased = 1 - pow(1 - t, 3)
            return walk.from + (resting - walk.from) * eased
        }
        if let stroll { return stroll.position(at: date) }
        return resting
    }

    private func walk(to index: Double, from position: Double) {
        stroll = nil
        resting = index
        walk = (position, .now, 0.6)
    }

    private func startStroll(lead: Double = 0) {
        guard walk == nil, dragPosition == nil, !shows.isEmpty, resting < lastIndex || lead > 0 else { return }
        stroll = FootprintYearsWalk(from: resting, start: .now, lead: lead, last: lastIndex)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = position(at: .now)
                    walk = nil
                    stroll = nil
                }
                let raw = (dragStart ?? 0) - value.translation.height / stepHeight
                // Past either end the corridor resists, like a scroll view's edge.
                let over = raw < 0 ? raw : (raw > lastIndex ? raw - lastIndex : 0)
                dragPosition = raw - over + over * 0.3
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                let from = dragPosition ?? start
                let projected = start - value.predictedEndTranslation.height / stepHeight
                dragStart = nil
                dragPosition = nil
                walk(to: min(max(projected.rounded(), 0), lastIndex), from: from)
            }
    }

    // MARK: - Chrome

    /// The year of the cover you're standing by.
    private func header(position: Double) -> some View {
        let year = currentShow(at: position).map { $0.timingCalendar().component(.year, from: $0.effectiveDate) }
        let summary = year.flatMap { yearSummaries[$0] }
        return VStack(alignment: .leading, spacing: 2) {
            if let year {
                Text(verbatim: String(year))
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .contentTransition(.numericText(value: Double(year)))
                if let summary {
                    Text(summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.7))
                }
            }
        }
        .animation(.snappy, value: year)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func infoCard(_ show: Show) -> some View {
        let dateLine = [footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()), FootprintTextNormalizer.nonEmptyTrimmed(show.city)]
            .compactMap { $0 }.joined(separator: " · ")
        return Button { detailTarget = FootprintDetailDestination(show: show) } label: {
            HStack(spacing: 14) {
                FootprintResolvedCoverImage(show: show, cover: covers[show.id])
                    .frame(width: 54, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text(dateLine)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(BSColor.Stage.muted)
                    if let venue = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) {
                        Text(venue).font(.system(size: 12)).foregroundStyle(BSColor.Stage.muted).lineLimit(1)
                    }
                    if !show.artistNames.isEmpty {
                        Text(show.artistNames.joined(separator: " / "))
                            .font(.system(size: 12))
                            .foregroundStyle(BSColor.Stage.dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .padding(14)
            .background(Color(white: 0.1).opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        }
        .buttonStyle(.plain)
    }
}

/// Walking on through the corridor by itself, in covers. The opening starts `lead` back and slows straight into the
/// stroll, so walking in and strolling on are one motion.
struct FootprintYearsWalk {
    /// Seconds the stroll spends on each cover.
    static let strollPace = 2.4
    static let openingLead = 2.5
    /// How quickly the lead is made up.
    private static let settle = 0.5

    let from: Double
    let start: Date
    var lead: Double = 0
    /// The oldest show, where the stroll stops.
    let last: Double

    func position(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(start))
        return min(last, from + elapsed / Self.strollPace) - lead * exp(-elapsed / Self.settle)
    }

    /// Until it stands still at the oldest show.
    var duration: Double { max((last - from) * Self.strollPace, lead > 0 ? 8 * Self.settle : 0) }
}

/// The corridor itself: covers alternating down the left and right walls, each turned a little towards you, fading
/// into haze with distance. Shared by the page and its entry tile.
struct FootprintGalleryHall: View {
    let shows: [Show]
    let covers: [UUID: FootprintCover]
    let position: Double
    var selectedID: UUID?
    /// Zooms the hall in, for small renderings such as the entry tile.
    var zoom: Double = 1
    var onTap: ((Show) -> Void)?

    /// Half the corridor's width, a cover's size and the walk from one cover to the next, in the hall's own units.
    private static let halfWidth = 0.55
    private static let coverSize = 0.6
    /// Covers hang in a high and a low row on each wall.
    private static let rowHeight = 0.36
    private static let step = 0.55
    /// How far ahead the cover you're standing by hangs.
    private static let near = 1.5
    /// Each cover turns this far off its wall towards the corridor.
    private static let turn = 35.0
    private static let ahead = 16

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let focal = min(size.width * 1.25, size.height * 0.7) * zoom
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.47)
            let lower = max(0, Int(position.rounded(.down)) - 1)
            let upper = min(shows.count - 1, Int(position.rounded(.down)) + Self.ahead)
            ZStack {
                walls(focal: focal, centre: centre)
                if lower <= upper {
                    ForEach(lower...upper, id: \.self) { index in
                        cover(shows[index], index: index, focal: focal, centre: centre)
                    }
                }
            }
        }
    }

    /// Faint lines where the walls meet the floor and ceiling, running to the vanishing point.
    private func walls(focal: Double, centre: CGPoint) -> some View {
        Canvas { context, _ in
            for side in [-1.0, 1.0] {
                for level in [-0.72, 0.72] {
                    let near = CGPoint(x: centre.x + side * focal * Self.halfWidth / 0.6, y: centre.y + focal * level / 0.6)
                    var path = Path()
                    path.move(to: near)
                    path.addLine(to: centre)
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.1), .white.opacity(0)]), startPoint: near, endPoint: centre
                    ), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cover(_ show: Show, index: Int, focal: Double, centre: CGPoint) -> some View {
        let depth = Self.near + (Double(index) - position) * Self.step
        if depth > 0.4 {
            let far = Self.near + Double(Self.ahead) * Self.step
            let side: Double = index.isMultiple(of: 2) ? -1 : 1
            // Left low, right high, left high, right low: the rows interleave down the corridor.
            let row: Double = (index / 2 + index % 2).isMultiple(of: 2) ? 1 : -1
            let lift = row * Self.rowHeight + (Double(show.id.uuid.0) / 255 - 0.5) * 0.06
            let edge = focal * Self.coverSize / depth
            // Seen from the corridor's centre, a cover turns more face-on the closer it is.
            let facing = 90 - Self.turn - atan(Self.halfWidth / depth) * 180 / .pi
            let haze = min(1, max(0, (depth - Self.near) / (far - Self.near)))
            let isSelected = selectedID == show.id
            Button { onTap?(show) } label: {
                FootprintResolvedCoverImage(show: show, cover: covers[show.id])
                    .frame(width: edge * 0.75, height: edge)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(isSelected ? BSColor.Stage.accent : .white.opacity(0.1), lineWidth: isSelected ? 2 : 0.5))
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            .rotation3DEffect(.degrees(side * facing), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            // Haze darkens rather than blurs: a blur per cover is an offscreen pass every frame.
            .brightness(-0.45 * haze)
            .opacity(min(1, max(0, (depth - 0.7) / 0.6)) * min(1, (far - depth) / 1.5))
            .position(x: centre.x + side * focal * Self.halfWidth / depth, y: centre.y + focal * lift / depth)
            .zIndex(-depth)
            .accessibilityLabel(show.name)
        }
    }
}
