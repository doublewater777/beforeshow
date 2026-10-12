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

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var position = ScrollPosition(edge: .top)
    @State private var scrolledDayID: UUID?
    /// A tap on empty lane space only proposes a slot; nothing is saved until the form is.
    @State private var ghost: Ghost?

    private struct Ghost: Equatable {
        let stageID: UUID
        let start: Date
    }

    private static let ruler = TimetableStyle.matrixRulerWidth
    private static let trailing: CGFloat = 12
    private static let laneGap: CGFloat = 8
    private static let minLane: CGFloat = 112
    private static let capHeight = TimetableStyle.matrixHeaderHeight
    private static let addStageWidth: CGFloat = 72

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var body: some View {
        let stages = day.orderedStages
        let performances = Dictionary(uniqueKeysWithValues: day.performances.map { ($0.id, $0) })
        let layout = TimetableMatrixLayout(
            stages: stages.map { stage in
                .init(id: stage.id, name: stage.name, performances: stage.performances.map {
                    .init(id: $0.id, artistName: $0.artistName, startsAt: $0.startsAt, endsAt: $0.endsAt, isInterested: $0.isInterested)
                })
            },
            now: now,
            calendar: calendar,
            emptyDayStart: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day.date)
        )

        GeometryReader { geo in
            let count = CGFloat(max(stages.count, 1))
            let lane = max(Self.minLane, (geo.size.width - Self.ruler - Self.trailing - Self.laneGap * (count - 1)) / count)
            let width = Self.ruler + lane * count + Self.laneGap * (count - 1) + Self.addStageWidth + Self.trailing
            let gridHeight = max(100, geo.size.height - Self.capHeight)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 1. Sticky Stage Headers Row (横向随列联动，纵向永远吸顶)
                    stageHeadersRow(stages: stages, lane: lane, layout: layout)
                        .frame(width: width, height: Self.capHeight, alignment: .leading)
                        .background(TimetableStyle.background)
                        .zIndex(10)

                    // 2. Vertical Timeline Grid
                    ScrollView(.vertical, showsIndicators: false) {
                        timelineGrid(layout: layout, lane: lane, performances: performances, stages: stages)
                            .frame(width: width, height: layout.contentHeight, alignment: .topLeading)
                            .background(ScrollViewBouncesConfigurator(bounces: false, directionalLock: true))
                    }
                    .scrollPosition($position)
                    .frame(width: width, height: gridHeight, alignment: .topLeading)
                    .clipped()
                    .background(ScrollViewBouncesConfigurator(bounces: false, directionalLock: true))
                }
                .frame(width: width, height: geo.size.height, alignment: .topLeading)
            }
            .background(ScrollViewBouncesConfigurator(bounces: false, directionalLock: true))
            .onChange(of: layout.nowY != nil, initial: true) { _, available in
                canReturnToNow = available
            }
            .onChange(of: returnToNowRequest) { _, _ in
                withAnimation(.snappy) { scrollToNow(layout, viewport: gridHeight) }
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

    private func scrollToNow(_ layout: TimetableMatrixLayout, viewport: CGFloat) {
        guard let nowY = layout.nowY else { position.scrollTo(edge: .top); return }
        position.scrollTo(y: max(0, nowY - viewport * 0.35))
    }

    // MARK: - Sticky Stage Headers Row

    private func soonMinutes(lane index: Int, layout: TimetableMatrixLayout) -> Int? {
        layout.cards.compactMap { card -> Int? in
            guard card.laneIndex == index, case .soon(let minutes) = card.status else { return nil }
            return minutes
        }.min()
    }

    private func stageHeadersRow(
        stages: [TimetableStage],
        lane: CGFloat,
        layout: TimetableMatrixLayout
    ) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let x = laneX(index, lane: lane)
                let tint = TimetableStageLight.color(stage.sortOrder)
                stageHeaderMenu(stage: stage, lane: lane, tint: tint, activity: layout.activity.indices.contains(index) ? layout.activity[index] : .idle, soonMinutes: soonMinutes(lane: index, layout: layout))
                    .offset(x: x, y: 0)
            }

            // "+ 舞台" top button
            Button(action: onManage) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(BSLocalization.text("舞台"))
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(TimetableStyle.muted)
                .frame(width: Self.addStageWidth, height: Self.capHeight - 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .offset(x: laneX(stages.count, lane: lane), y: 4)
        }
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
            // 1. Time markings on the left (scroll vertically with the content)
            ForEach(layout.hours, id: \.date) { mark in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimetableTimeFormat.time(mark.date, timeZone: timeZone))
                        .font(TimetableStyle.mono(11))
                        .lineLimit(1)
                    if mark.isMidnight {
                        Image(systemName: "moon.fill")
                            .font(BSFont.V3.caption)
                    }
                }
                .foregroundStyle(mark.isMidnight ? TimetableStyle.night : TimetableStyle.muted)
                .frame(width: Self.ruler - 4, alignment: .trailing)
                .offset(x: 0, y: mark.y - 8)
            }

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
                        // Light means "on stage now": only a playing stage is lit from its header.
                        if activity == .live {
                            TimetableStageBeam(color: tint)
                                .frame(height: 320, alignment: .top)
                                .allowsHitTesting(false)
                        }
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
            ForEach(layout.cards) { card in
                let x = laneX(card.laneIndex, lane: lane)
                let y = card.top
                let performance = performances[card.id]
                let isInterested = performance?.isInterested ?? card.isInterested

                TimetableMatrixCard(
                    card: card,
                    width: lane,
                    avatarURL: performances[card.id].flatMap(avatarURL),
                    artistID: performances[card.id]?.appleMusicArtistID,
                    isGhost: wantOnly && !card.isInterested,
                    nowOffset: card.status == .live ? layout.nowY.map { $0 - card.top } : nil,
                    stageTint: TimetableStageLight.color(day.orderedStages[card.laneIndex].sortOrder),
                    timeZone: timeZone,
                    onSelect: {
                        if let performance = performances[card.id] {
                            onSelectPerformance(performance)
                        }
                    },
                    onToggle: {
                        if let performance = performances[card.id] {
                            onToggleInterested(performance)
                        }
                    }
                )
                .offset(x: x, y: y)
                .zIndex(1)
            }

            if let ghost, let index = stages.firstIndex(where: { $0.id == ghost.stageID }) {
                ghostSlot(ghost, stage: stages[index], lane: lane, layout: layout)
                    .offset(x: laneX(index, lane: lane), y: layout.y(for: ghost.start))
                    .zIndex(2)
            }

            // 5. Live now line and ruler time badge: the page's one red marker. The line runs
            // under the cards so it never strikes through a name; live cards carry their own glow.
            if let nowY = layout.nowY {
                let actualNowY = nowY - 9
                Rectangle()
                    .fill(TimetableStyle.now)
                    .frame(width: laneX(laneCount, lane: lane) - Self.ruler - Self.laneGap, height: 2)
                    .shadow(color: TimetableStyle.now.opacity(0.7), radius: 5)
                    .offset(x: Self.ruler, y: actualNowY)
                    .allowsHitTesting(false)
                    .zIndex(0.8)

                // Current time badge on the ruler
                Text(TimetableTimeFormat.time(now, timeZone: timeZone))
                    .font(TimetableStyle.mono(10.5, weight: .bold))
                    .foregroundStyle(TimetableStyle.background)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TimetableStyle.now))
                    .shadow(color: TimetableStyle.now.opacity(0.6), radius: 4)
                    .offset(x: 2, y: actualNowY - 7)
                    .allowsHitTesting(false)
                    .zIndex(3)
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

    /// Header light mirrors the lane: a playing stage glows in its colour, a stage
    /// starting soon lights only its bottom edge and says when, idle stays dark.
    private func stageHeaderMenu(
        stage: TimetableStage,
        lane: CGFloat,
        tint: Color,
        activity: TimetableMatrixLayout.Activity,
        soonMinutes: Int?
    ) -> some View {
        Menu {
            Button {
                onAddPerformance(stage, nil)
            } label: {
                Label(BSLocalization.text("在此舞台添加演出"), systemImage: "plus")
            }
            Button(action: onManage) {
                Label(BSLocalization.text("管理天数与舞台"), systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 6) {
                if activity == .live {
                    TimetableEqualizer(color: tint)
                } else {
                    TimetableStageLight.marker(stage.sortOrder).fill(tint).frame(width: 7, height: 7)
                }
                Text(stage.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if activity == .soon, let soonMinutes {
                    Text(BSLocalization.format("%d 分钟后", soonMinutes))
                        .font(TimetableStyle.mono(10.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(activity == .live ? TimetableStyle.foreground : TimetableStyle.muted)
            .padding(.horizontal, BSSpacing.sm)
            .frame(width: lane, height: Self.capHeight)
            .background {
                TimetableStyle.lane
                    .overlay(tint.opacity(activity == .live ? 0.16 : 0))
                    .overlay(alignment: .bottom) {
                        if activity != .idle {
                            Rectangle().fill(tint.opacity(activity == .live ? 0.5 : 0.55)).frame(height: activity == .live ? 1 : 1.5)
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: TimetableStyle.matrixLaneRadius,
                        topTrailingRadius: TimetableStyle.matrixLaneRadius
                    ))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Light falling from a playing stage's header, breathing slowly.
private struct TimetableStageBeam: View {
    let color: Color
    @State private var breathe = false

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: color.opacity(0.22), location: 0),
                .init(color: color.opacity(0.08), location: 0.4),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(breathe ? 1 : 0.75)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.75).repeatForever(autoreverses: true)) { breathe = true }
        }
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
