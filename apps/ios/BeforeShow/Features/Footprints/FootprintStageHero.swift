import SwiftUI

/// The top of a show's page: its poster is the LED wall, moving heads sweep in the poster's colours.
struct FootprintStageHero: View {
    let show: Show
    let cover: FootprintCover?
    let archive: FootprintArchiveSnapshot
    let identity: FootprintDetailIdentity
    let canOpenCover: Bool
    let coverTransition: Namespace.ID
    let onOpenCover: () -> Void

    @State private var lights = FootprintStageLights.fallback
    @State private var powered = false
    @State private var showsFullLineup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private static let chipLimit = 10

    /// The longest-standing reunion on the bill, said under the ticket.
    private var reunionLine: String? {
        FootprintStagePolicy.reunions(for: show, in: archive.shows)
            .filter { $0.nth > 1 }
            .max { $0.nth < $1.nth }
            .map { BSLocalization.format("和%@第 %lld 次见面 · 点票根撕下", $0.name, $0.nth) }
    }

    private static let stageHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
                .padding(.horizontal, -BSSpacing.roomy)
            info.padding(.top, 18)
            reunionChips.padding(.top, 14)
            if showsFullLineup {
                ArtistLineupStrip(artists: show.artists)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            FootprintTicketStub(show: show, ordinal: identity.showOrdinal, lights: colors, reunionLine: reunionLine)
                .padding(.top, 22)
        }
        .task(id: show.id) {
            await sampleLights()
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08).delay(0.25)) { powered = true }
        }
    }

    private var colors: [Color] {
        lights.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Color(red: 0.024, green: 0.02, blue: 0.02)
                RadialGradient(colors: [colors[0].opacity(0.18), .clear], center: .init(x: 0.5, y: 0.72), startRadius: 0, endRadius: width * 0.8)
                ledWall.position(x: width / 2, y: 64 + 112)
                beams(width: width)
                    .opacity(powered ? 1 : 0)
                    .allowsHitTesting(false)
                truss(width: width)
                FootprintCrowdSilhouette()
                    .fill(Color(red: 0.024, green: 0.02, blue: 0.02))
                    .frame(height: 70)
                    .position(x: width / 2, y: Self.stageHeight - 35)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: Self.stageHeight)
        .clipped()
    }

    @ViewBuilder
    private var ledWall: some View {
        let wall = FootprintCoverView(show: show, cover: cover, showsMetadata: false)
            .frame(width: 168, height: 224)
            .overlay {
                // LED pitch: fine horizontal scanlines over the poster.
                Canvas { canvas, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        canvas.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.28)))
                        y += 3
                    }
                }
                .allowsHitTesting(false)
            }
            .shadow(color: colors[0].opacity(0.45), radius: 30)
            .shadow(color: colors[1].opacity(0.2), radius: 70)
        if canOpenCover {
            Button(action: onOpenCover) {
                wall.bsTransitionSource(id: "cover", in: coverTransition)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("查看封面大图"))
        } else {
            wall.accessibilityHidden(true)
        }
    }

    private func beams(width: CGFloat) -> some View {
        let fixtures: [(x: CGFloat, base: Double, swing: Double, speed: Double, phase: Double, light: Int)] = [
            (0.12, -4, 20, 1.15, 0, 1), (0.37, 4, 17, 1.5, 1.3, 0),
            (0.63, -4, 17, 1.37, 2.2, 0), (0.88, 4, 20, 1.23, 3.1, 1)
        ]
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(fixtures.indices, id: \.self) { index in
                    let fixture = fixtures[index]
                    let angle = fixture.base + (reduceMotion ? 0 : fixture.swing * sin(t * fixture.speed + fixture.phase))
                    FootprintBeam()
                        .fill(LinearGradient(colors: [colors[fixture.light].opacity(0.6), colors[fixture.light].opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 150, height: Self.stageHeight)
                        .blur(radius: 2)
                        .rotationEffect(.degrees(angle), anchor: .top)
                        .position(x: width * fixture.x, y: 24 + Self.stageHeight / 2)
                        .blendMode(.screen)
                }
            }
        }
    }

    private func truss(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Canvas { canvas, size in
                canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
                var x: CGFloat = -size.height
                while x < size.width {
                    var strut = Path()
                    strut.move(to: CGPoint(x: x, y: size.height))
                    strut.addLine(to: CGPoint(x: x + size.height, y: 0))
                    canvas.stroke(strut, with: .color(Color(white: 0.24)), lineWidth: 1.2)
                    x += 9
                }
            }
            .frame(height: 12)
            HStack {
                ForEach(0..<4, id: \.self) { index in
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                        .fill(Color(white: 0.11))
                        .frame(width: 22, height: 14)
                        .shadow(color: colors[index == 1 || index == 2 ? 0 : 1].opacity(powered ? 0.7 : 0), radius: 8, y: 6)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, width * 0.02)
            .offset(y: 10)
        }
        .frame(width: width)
        .position(x: width / 2, y: 18)
        .accessibilityHidden(true)
    }

    // MARK: Text

    private var info: some View {
        let calendar = show.timingCalendar()
        let date = footprintFullDateText(show.effectiveDate, calendar: calendar)
        let weekday = Self.weekday(show.effectiveDate, calendar: calendar)
        let place = [FootprintTextNormalizer.nonEmptyTrimmed(show.venueName), FootprintTextNormalizer.nonEmptyTrimmed(show.city)]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "No. %03d · %@ %@", identity.showOrdinal, date, weekday))
                .font(.system(size: 12, weight: .medium).width(.condensed).monospacedDigit())
                .tracking(2.5)
                .foregroundStyle(colors[1])
            Text(show.name)
                .font(.system(size: 27, weight: .heavy, design: .serif))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            if !place.isEmpty {
                Text(place)
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(2)
            }
            if let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city), let cityOrdinal = identity.cityOrdinal {
                Text(BSLocalization.format("第 %lld 场现场", identity.showOrdinal) + "  ·  " + "\(city) · " + BSLocalization.format("第 %lld 场", cityOrdinal))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent.opacity(0.88))
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var reunionChips: some View {
        // Reunions first, so "第 N 次" chips are never cut off by the limit.
        let reunions = FootprintStagePolicy.reunions(for: show, in: archive.shows)
            .enumerated().sorted { ($0.element.nth > 1 ? 0 : 1, $0.offset) < ($1.element.nth > 1 ? 0 : 1, $1.offset) }
            .map(\.element)
        if !reunions.isEmpty {
            FootprintFlowLayout(spacing: 6) {
                ForEach(reunions.prefix(Self.chipLimit), id: \.name) { reunion in
                    Button {
                        if let link = show.artists.first(where: { $0.name == reunion.name })?.appleMusicURL,
                           let url = URL(string: link) {
                            openURL(url)
                        }
                    } label: {
                    HStack(spacing: 5) {
                        Text(reunion.name).lineLimit(1)
                        if reunion.nth > 1 {
                            Text(BSLocalization.format("第 %lld 次", reunion.nth))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(colors[1])
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(reunion.nth > 1 ? BSColor.Stage.heroIvory : BSColor.Stage.foreground.opacity(0.75))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(reunion.nth > 1 ? colors[1].opacity(0.1) : Color.white.opacity(0.06), in: Capsule())
                    .overlay { if reunion.nth > 1 { Capsule().stroke(colors[1].opacity(0.35)) } }
                    }
                    .buttonStyle(.plain)
                }
                if show.artists.count > Self.chipLimit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showsFullLineup.toggle() }
                    } label: {
                        HStack(spacing: 2) {
                            Text(BSLocalization.format("全部 %lld 位", show.artists.count))
                            Image(systemName: showsFullLineup ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Lights

    private func sampleLights() async {
        guard let cover else { return }
        let image: UIImage?
        switch cover.source {
        case let .local(url):
            image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        case let .remote(url):
            image = await ShowCoverImageCache.shared.image(from: url)
        case .archive:
            image = nil
        }
        guard let image else { return }
        let picked = await Task.detached(priority: .utility) {
            FootprintStageLights.pick(from: FootprintStageLights.sample(image))
        }.value
        withAnimation(.easeInOut(duration: 0.6)) { lights = picked }
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
}

/// A moving-head beam: narrow at the lamp, wide on the floor.
private struct FootprintBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Heads and raised hands along the front of the stage.
private struct FootprintCrowdSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let heads = 14
        let step = rect.width / CGFloat(heads)
        for index in 0...heads {
            let x = rect.minX + CGFloat(index) * step
            let lift: CGFloat = index % 3 == 0 ? 0.25 : index % 2 == 0 ? 0.45 : 0.4
            path.addQuadCurve(to: CGPoint(x: x + step / 2, y: rect.minY + rect.height * lift),
                              control: CGPoint(x: x + step * 0.1, y: rect.minY + rect.height * (lift - 0.15)))
            if index % 4 == 1 {
                // A raised arm with a hand.
                let wrist = CGPoint(x: x + step * 0.62, y: rect.minY + rect.height * 0.12)
                path.addLine(to: CGPoint(x: x + step * 0.52, y: rect.minY + rect.height * lift))
                path.addQuadCurve(to: wrist, control: CGPoint(x: x + step * 0.5, y: rect.minY + rect.height * 0.2))
                path.addEllipse(in: CGRect(x: wrist.x - 3, y: wrist.y - 5, width: 6, height: 8))
                path.move(to: wrist)
                path.addQuadCurve(to: CGPoint(x: x + step * 0.7, y: rect.minY + rect.height * lift),
                                  control: CGPoint(x: x + step * 0.7, y: rect.minY + rect.height * 0.25))
            }
            path.addQuadCurve(to: CGPoint(x: x + step, y: rect.minY + rect.height * 0.5),
                              control: CGPoint(x: x + step * 0.9, y: rect.minY + rect.height * (lift - 0.1)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Wraps chips onto as many lines as they need.
struct FootprintFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append((current, y, x - spacing, height))
                y += height + spacing
                current = []; x = 0; height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, height)) }
        return rows
    }
}
