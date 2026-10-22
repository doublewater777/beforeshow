import SwiftUI

/// Stage-per-column matrix, each stage lit in its own colour.
/// - Stage header and lane body form a unified pillar per stage (no detached floating overlay).
/// - Canvas scrolls with directional lock and no elastic bounce.
struct TimetableStageMatrixView: View {
    let day: TimetableDay
    let now: Date
    let timeZone: TimeZone
    let wantOnly: Bool
    @Binding var canReturnToNow: Bool
    let returnToNowRequest: Int
    let avatarURL: (TimetablePerformance) -> URL?
    let onSelectPerformance: (TimetablePerformance) -> Void
    let onToggleInterested: (TimetablePerformance) -> Void
    let onAddPerformance: (TimetableStage, Date?) -> Void
    let onManage: () -> Void
    let onRenameStage: (TimetableStage, String) -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var position = BSScrollController()
    @State private var scrolledDayID: UUID?
    /// A tap on empty lane space only proposes a slot; nothing is saved until the form is.
    @State private var ghost: Ghost?
    @State private var viewport = TimetableMatrixViewport()

    private struct Ghost: Equatable {
        let stageID: UUID
        let start: Date
    }

    private static let ruler = TimetableStyle.matrixRulerWidth
    private static let trailing = TimetableStyle.matrixTrailingInset
    private static let laneGap = TimetableStyle.matrixLaneGap
    private static let minLane = TimetableStyle.matrixMinimumLaneWidth
    private static let capHeight = TimetableStyle.matrixHeaderHeight
    private static let addStageWidth = TimetableStyle.matrixAddStageWidth

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    init(
        day: TimetableDay,
        now: Date,
        timeZone: TimeZone,
        wantOnly: Bool,
        canReturnToNow: Binding<Bool>,
        returnToNowRequest: Int,
        avatarURL: @escaping (TimetablePerformance) -> URL?,
        onSelectPerformance: @escaping (TimetablePerformance) -> Void,
        onToggleInterested: @escaping (TimetablePerformance) -> Void,
        onAddPerformance: @escaping (TimetableStage, Date?) -> Void,
        onManage: @escaping () -> Void,
        onRenameStage: @escaping (TimetableStage, String) -> Void = { _, _ in }
    ) {
        self.day = day
        self.now = now
        self.timeZone = timeZone
        self.wantOnly = wantOnly
        self._canReturnToNow = canReturnToNow
        self.returnToNowRequest = returnToNowRequest
        self.avatarURL = avatarURL
        self.onSelectPerformance = onSelectPerformance
        self.onToggleInterested = onToggleInterested
        self.onAddPerformance = onAddPerformance
        self.onManage = onManage
        self.onRenameStage = onRenameStage
    }

    var body: some View {
        let stages = day.orderedStages
        let isSingleStage = stages.count == 1
        let addStageWidth = isSingleStage ? 0 : Self.addStageWidth
        let performances = Dictionary(uniqueKeysWithValues: stages.flatMap(\.performances).map { ($0.id, $0) })
        let layout = TimetableMatrixLayout(
            stages: stages.map { stage in
                .init(id: stage.id, name: stage.name, performances: stage.performances.map {
                    .init(id: $0.id, artistName: $0.artistName, startsAt: $0.startsAt, endsAt: $0.endsAt, isInterested: $0.isInterested)
                })
            },
            now: now,
            calendar: calendar,
            pointsPerMinute: isSingleStage ? TimetableStyle.matrixSingleStagePointsPerMinute : TimetableMatrixLayout.pointsPerMinute,
            emptyDayStart: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day.date)
        )

        GeometryReader { geo in
            let count = CGFloat(max(stages.count, 1))
            let lane = max(Self.minLane, (geo.size.width - Self.ruler - Self.trailing - Self.laneGap * (count - 1)) / count)
            let width = Self.ruler + lane * count + Self.laneGap * (count - 1) + addStageWidth + Self.trailing
            let gridHeight = max(100, geo.size.height - Self.capHeight)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 1. Sticky Stage Headers Row (横向随列联动，纵向永远吸顶)
                    TimetableMatrixHeadersView(
                        stages: stages, lane: lane, layout: layout, viewport: viewport, showsAddStage: !isSingleStage,
                        onAddPerformance: onAddPerformance, onRenameStage: onRenameStage, onManage: onManage
                    )
                        .frame(width: width, height: Self.capHeight, alignment: .leading)
                        .zIndex(10)

                    // 2. Vertical Timeline Grid
                    ScrollView(.vertical, showsIndicators: false) {
                        timelineGrid(layout: layout, lane: lane, performances: performances, stages: stages)
                            .frame(width: width, height: layout.contentHeight, alignment: .topLeading)
                            .background(BSScrollObservation(enclosing: true, controller: position) { offset in
                                viewport.updateVerticalOffset(offset.y)
                            })
                            .background(ScrollViewBouncesConfigurator(bounces: false, directionalLock: true))
                    }
                    .frame(width: width, height: gridHeight, alignment: .topLeading)
                    .clipped()
                    .background(ScrollViewBouncesConfigurator(bounces: false, directionalLock: true))
                }
                .frame(width: width, height: geo.size.height, alignment: .topLeading)
                .bsOnScrollOffset(enclosing: true) { viewport.updateHorizontalOffset($0.x) }
            }
            .onChange(of: CGSize(width: geo.size.width, height: gridHeight), initial: true) { _, size in
                viewport.updateSize(size)
            }
            .background(ScrollViewBouncesConfigurator(bounces: false, directionalLock: true))
            .onChange(of: layout.nowY != nil, initial: true) { _, available in
                canReturnToNow = available
            }
            .onChange(of: returnToNowRequest) { _, _ in
                scrollToNow(layout, viewport: gridHeight, animated: true)
            }
            // The sheet reports a tiny height while presenting; wait for the real one.
            .onChange(of: [day.id.hashValue, Int(geo.size.height)], initial: true) {
                let minimumHeight = verticalSizeClass == .compact ? Self.capHeight + BSLayout.minTouchTarget : 300
                guard geo.size.height > minimumHeight, scrolledDayID != day.id else { return }
                scrolledDayID = day.id
                scrollToNow(layout, viewport: gridHeight)
            }
        }
        .clipped()
    }

    private func laneX(_ index: Int, lane: CGFloat) -> CGFloat {
        Self.ruler + CGFloat(index) * (lane + Self.laneGap)
    }

    private func scrollToNow(_ layout: TimetableMatrixLayout, viewport: CGFloat, animated: Bool = false) {
        guard let nowY = layout.nowY else { position.scrollTo(y: 0); return }
        position.scrollTo(y: max(0, nowY - viewport * 0.35), animated: animated)
    }

    // MARK: - Timeline Grid

    private func timelineGrid(
        layout: TimetableMatrixLayout,
        lane: CGFloat,
        performances: [UUID: TimetablePerformance],
        stages: [TimetableStage]
    ) -> some View {
        let laneCount = stages.count
        let laneHeight = max(layout.laneHeight, layout.contentHeight - 24)
        return ZStack(alignment: .topLeading) {
            // 1. Pinned Time Ruler on the left (fixed horizontally, scrolls vertically with timeline)
            TimetableMatrixRulerView(
                layout: layout,
                timeZone: timeZone,
                now: now,
                viewport: viewport
            )
            .zIndex(10)

            // 2. Stage column backgrounds with atmospheric lighting and empty area tap-to-add
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let x = laneX(index, lane: lane)
                let tint = TimetableStageLight.color(stage.sortOrder)
                let activity = layout.activity.indices.contains(index) ? layout.activity[index] : .idle

                UnevenRoundedRectangle(
                    bottomLeadingRadius: TimetableStyle.matrixLaneRadius,
                    bottomTrailingRadius: TimetableStyle.matrixLaneRadius
                )
                    .fill(TimetableStyle.lane)
                    .overlay(alignment: .top) {
                        TimetableStageBeam(color: tint, activity: activity, index: index)
                            .allowsHitTesting(false)
                    }
                    .frame(width: lane, height: laneHeight)
                    .clipShape(UnevenRoundedRectangle(
                        bottomLeadingRadius: TimetableStyle.matrixLaneRadius,
                        bottomTrailingRadius: TimetableStyle.matrixLaneRadius
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard !wantOnly else { return }
                        let seconds = (layout.date(for: location.y).timeIntervalSinceReferenceDate / 900).rounded(.down) * 900
                        let proposal = Ghost(stageID: stage.id, start: Date(timeIntervalSinceReferenceDate: seconds))
                        withAnimation(.snappy(duration: 0.2)) { ghost = ghost == proposal ? nil : proposal }
                    }
                    .offset(x: x, y: 0)
                    .zIndex(0)

                if let midnight = layout.midnightY {
                    UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                        .fill(BSColor.Stage.glowBlue.opacity(0.09))
                        .frame(width: lane, height: max(0, laneHeight - midnight))
                        .offset(x: x, y: midnight)
                        .allowsHitTesting(false)
                        .zIndex(-2)
                }
            }

            // Already-played time sits slightly darker than what is still to come.
            if let nowY = layout.nowY {
                Rectangle()
                    .fill(TimetableStyle.background.opacity(0.4))
                    .frame(width: laneX(laneCount, lane: lane) - Self.ruler - Self.laneGap, height: max(0, nowY))
                    .offset(x: Self.ruler)
                    .allowsHitTesting(false)
                    .zIndex(0.5)
            }

            // 3. Timeline Auxiliary Guide Lines across all stage lanes (正点虚线，严格置于现场块底层)
            timelineGuideLines(layout: layout, laneCount: laneCount, lane: lane)
                .zIndex(-1)

            // 4. Performance Cards (现场块)
            TimetableMatrixCardsView(
                layout: layout, lane: lane, performances: performances, stages: stages,
                viewport: viewport, wantOnly: wantOnly, timeZone: timeZone,
                avatarURL: avatarURL, onSelect: onSelectPerformance, onToggle: onToggleInterested
            )
            .zIndex(1)

            if let ghost, let index = stages.firstIndex(where: { $0.id == ghost.stageID }) {
                ghostSlot(ghost, stage: stages[index], lane: lane, layout: layout)
                    .offset(x: laneX(index, lane: lane), y: layout.y(for: ghost.start))
                    .zIndex(2)
            }

            // 5. Live now line across stage lanes
            if let nowY = layout.nowY {
                let actualNowY = nowY - 9
                Rectangle()
                    .fill(TimetableStyle.now)
                    .frame(width: laneX(laneCount, lane: lane) - Self.ruler - Self.laneGap, height: 2)
                    .shadow(color: TimetableStyle.now.opacity(0.7), radius: 5)
                    .offset(x: Self.ruler, y: actualNowY)
                    .allowsHitTesting(false)
                    .zIndex(0.8)
            }
        }
        .animation(.easeOut(duration: 0.35), value: wantOnly)
        .onChange(of: day.id) { _, _ in ghost = nil }
        .onChange(of: wantOnly) { _, _ in ghost = nil }
    }

    private func ghostSlot(_ ghost: Ghost, stage: TimetableStage, lane: CGFloat, layout: TimetableMatrixLayout) -> some View {
        let tint = TimetableStageLight.color(stage.sortOrder)
        return Button {
            self.ghost = nil
            onAddPerformance(stage, ghost.start)
        } label: {
            VStack(spacing: 4) {
                Label(BSLocalization.text("添加演出"), systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)
                Text(BSLocalization.format("%@ 开始", TimetableTimeFormat.time(ghost.start, timeZone: timeZone)))
                    .font(TimetableStyle.mono(11))
                    .foregroundStyle(tint)
            }
            .frame(width: lane, height: 45 * layout.pointsPerMinute - TimetableMatrixLayout.cardSpacing)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tint.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(TimetablePressStyle())
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Timeline Guide Lines

    private func timelineGuideLines(
        layout: TimetableMatrixLayout,
        laneCount: Int,
        lane: CGFloat
    ) -> some View {
        let startX = Self.ruler
        let totalWidth = laneX(laneCount, lane: lane) - Self.laneGap - startX

        return Group {
            ForEach(layout.hours, id: \.date) { mark in
                let lineY = mark.y

                // 正点虚线辅助线 (:00)
                HorizontalDashedLine()
                    .stroke(
                        mark.isMidnight
                            ? TimetableStyle.night.opacity(0.40)
                            : Color.white.opacity(0.14),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .frame(width: totalWidth, height: 1)
                    .offset(x: startX, y: lineY)
            }
        }
        .allowsHitTesting(false)
    }

}

/// Completely disables elastic bouncing and locks scrolling to a single axis.
private struct ScrollViewBouncesConfigurator: UIViewRepresentable {
    var bounces: Bool = false
    var directionalLock: Bool = true

    func makeUIView(context: Context) -> BouncesConfigurationView {
        let view = BouncesConfigurationView()
        view.bounces = bounces
        view.directionalLock = directionalLock
        return view
    }

    func updateUIView(_ uiView: BouncesConfigurationView, context: Context) {
        uiView.bounces = bounces
        uiView.directionalLock = directionalLock
        uiView.apply()
    }
}

private final class BouncesConfigurationView: UIView {
    var bounces: Bool = false {
        didSet { apply() }
    }
    var directionalLock: Bool = true {
        didSet { apply() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        apply()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    func apply() {
        var current: UIView? = self.superview
        while let v = current {
            if let sv = v as? UIScrollView {
                configure(sv)
                return
            }
            if let sv = v.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                configure(sv)
                return
            }
            current = v.superview
        }
    }

    private func configure(_ sv: UIScrollView) {
        sv.bounces = bounces
        sv.alwaysBounceVertical = bounces
        sv.alwaysBounceHorizontal = bounces
        sv.bouncesZoom = false
        sv.isDirectionalLockEnabled = directionalLock
    }
}

/// Tapered cone representing a theatrical spotlight beam.
private struct StageBeamConeShape: Shape {
    var topWidthRatio: CGFloat = 0.35
    var bottomWidthRatio: CGFloat = 0.90

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topWidth = rect.width * topWidthRatio
        let bottomWidth = rect.width * bottomWidthRatio
        let topLeading = (rect.width - topWidth) / 2
        let bottomLeading = (rect.width - bottomWidth) / 2

        path.move(to: CGPoint(x: topLeading, y: rect.minY))
        path.addLine(to: CGPoint(x: topLeading + topWidth, y: rect.minY))
        path.addLine(to: CGPoint(x: bottomLeading + bottomWidth, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomLeading, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Theatrical stage light beam: atmospheric moving-head cone beams and truss wash.
/// When live, energetic and focused; when idle (no performance), soft atmospheric
/// crossing stage light beams cutting through the haze with gentle breathing and swaying.
///
/// Performance: each beam is blurred once into a cached `drawingGroup` texture; breathing
/// and swaying only animate opacity and rotation on top of it, so neither the endless
/// animation nor scrolling re-runs the blur every frame.
private struct TimetableStageBeam: View {
    let color: Color
    let activity: TimetableMatrixLayout.Activity
    let index: Int

    @State private var breathe = false
    @State private var sway = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { activity == .live }
    private var isSoon: Bool {
        if case .soon = activity { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Ambient truss wash
            wash
                .frame(height: isLive ? 360 : 300)

            // 2. Primary angled spotlight beam (主现场光束)
            primaryBeam
                .frame(height: isLive ? 440 : 380)

            // 3. Ambient crossing beam for atmospheric depth (交叉氛围光束)
            crossingBeam
                .frame(height: isLive ? 380 : 320)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: isLive ? 2.4 : 4.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: isLive ? 3.2 : 6.0).repeatForever(autoreverses: true)) {
                sway = true
            }
        }
    }

    /// Opacity at the dim end of a breath, relative to the bright end.
    private var breatheFloor: Double {
        if isLive { return 0.72 }
        if isSoon { return 0.65 }
        return 0.55
    }

    private var wash: some View {
        let top: Double = isLive ? 0.30 : isSoon ? 0.20 : 0.13
        let mid: Double = isLive ? 0.12 : isSoon ? 0.08 : 0.05
        return LinearGradient(
            stops: [
                .init(color: color.opacity(top), location: 0),
                .init(color: color.opacity(mid), location: 0.35),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(breathe ? 1 : breatheFloor)
    }

    private var primaryBeam: some View {
        let baseAngle = (index % 2 == 0 ? -1.0 : 1.0) * (isLive ? 6.0 : 8.5)
        let swayAngle = (sway ? 2.8 : -2.8) * (index % 2 == 0 ? 1.0 : -1.0)
        let angle = reduceMotion ? baseAngle : (baseAngle + swayAngle)

        return beam(
            topWidthRatio: isLive ? 0.45 : 0.30,
            bottomWidthRatio: isLive ? 0.95 : 0.85,
            topOpacity: isLive ? 0.28 : 0.15,
            midOpacity: isLive ? 0.12 : 0.06,
            midLocation: 0.4,
            blur: isLive ? 7 : 10
        )
        .opacity(breathe ? 1 : (isLive ? 0.7 : 0.6))
        .rotationEffect(.degrees(angle), anchor: .top)
    }

    private var crossingBeam: some View {
        let baseAngle = (index % 2 == 0 ? 1.0 : -1.0) * (isLive ? 7.5 : 9.5)
        let swayAngle = (sway ? -2.2 : 2.2) * (index % 2 == 0 ? 1.0 : -1.0)
        let angle = reduceMotion ? baseAngle : (baseAngle + swayAngle)

        return beam(
            topWidthRatio: 0.25,
            bottomWidthRatio: 0.75,
            topOpacity: isLive ? 0.16 : 0.08,
            midOpacity: isLive ? 0.06 : 0.03,
            midLocation: 0.45,
            blur: 12
        )
        .opacity(breathe ? 1 : 0.6)
        .rotationEffect(.degrees(angle), anchor: .top)
    }

    /// A soft cone rendered once into an offscreen texture. Inputs only change with
    /// the stage's live/idle state, never per animation frame.
    private func beam(
        topWidthRatio: CGFloat,
        bottomWidthRatio: CGFloat,
        topOpacity: Double,
        midOpacity: Double,
        midLocation: CGFloat,
        blur: CGFloat
    ) -> some View {
        StageBeamConeShape(topWidthRatio: topWidthRatio, bottomWidthRatio: bottomWidthRatio)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: color.opacity(topOpacity), location: 0),
                        .init(color: color.opacity(midOpacity), location: midLocation),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: blur)
            .drawingGroup()
    }
}

private struct HorizontalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
