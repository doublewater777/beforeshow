import SwiftUI

/// Stage-per-column matrix, each stage lit in its own colour;
/// stages playing right now are lit from their header.
struct TimetableStageMatrixView: View {
    let day: TimetableDay
    let now: Date
    let timeZone: TimeZone
    let wantOnly: Bool
    let avatarURL: (String) -> URL?
    let onToggleInterested: (TimetablePerformance) -> Void

    @State private var position = ScrollPosition(edge: .top)
    @State private var scrolledDayID: UUID?

    private static let ruler: CGFloat = 48
    private static let trailing: CGFloat = 12
    private static let laneGap: CGFloat = 6
    private static let minLane: CGFloat = 104
    private static let capHeight: CGFloat = 38

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
            calendar: calendar
        )

        GeometryReader { geo in
            let count = CGFloat(max(stages.count, 1))
            let lane = max(Self.minLane, (geo.size.width - Self.ruler - Self.trailing - Self.laneGap * (count - 1)) / count)
            let width = Self.ruler + lane * count + Self.laneGap * (count - 1) + Self.trailing

            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        canvas(layout: layout, lane: lane, performances: performances)
                            .frame(width: width, height: layout.contentHeight, alignment: .topLeading)
                    } header: {
                        caps(stages: stages, layout: layout, lane: lane)
                            .frame(width: width, height: Self.capHeight, alignment: .topLeading)
                    }
                }
            }
            .scrollPosition($position)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // The sheet reports a tiny height while presenting; wait for the real one.
            .onChange(of: [day.id.hashValue, Int(geo.size.height)], initial: true) {
                guard geo.size.height > 300, scrolledDayID != day.id else { return }
                scrolledDayID = day.id
                scrollToNow(layout, viewport: geo.size.height)
            }
        }
        .clipped()
    }

    private func laneX(_ index: Int, lane: CGFloat) -> CGFloat {
        Self.ruler + CGFloat(index) * (lane + Self.laneGap)
    }

    /// Puts the now line at ~40% of the viewport: what just happened above, the next hour or two below.
    private func scrollToNow(_ layout: TimetableMatrixLayout, viewport: CGFloat) {
        guard let nowY = layout.nowY else { position.scrollTo(edge: .top); return }
        position.scrollTo(y: max(0, nowY + Self.capHeight - viewport * 0.4))
    }

    // MARK: - Header

    private func caps(stages: [TimetableStage], layout: TimetableMatrixLayout, lane: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TimetableStyle.background
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let activity = layout.activity.indices.contains(index) ? layout.activity[index] : .idle
                let tint = TimetableStageLight.color(stage.sortOrder)
                HStack(spacing: 6) {
                    if activity == .live {
                        TimetableEqualizer(color: tint)
                    } else {
                        TimetableStageLight.marker(stage.sortOrder).fill(tint).frame(width: 7, height: 7)
                    }
                    Text(stage.name)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(activity == .live ? TimetableStyle.foreground : TimetableStyle.muted)
                .shadow(color: tint.opacity(activity == .live ? 0.55 : 0), radius: 6)
                .frame(width: lane, height: Self.capHeight)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                        .fill(activity == .live ? AnyShapeStyle(tint.opacity(0.12)) : AnyShapeStyle(TimetableStyle.lane))
                )
                .overlay(alignment: .top) {
                    if activity != .idle {
                        TimetableStageBeam(isLive: activity == .live, color: tint)
                            .frame(width: lane + 36, height: 260)
                    }
                }
                .offset(x: laneX(index, lane: lane))
            }
        }
    }

    // MARK: - Canvas

    private func canvas(layout: TimetableMatrixLayout, lane: CGFloat, performances: [UUID: TimetablePerformance]) -> some View {
        let laneCount = day.orderedStages.count
        return ZStack(alignment: .topLeading) {
            ForEach(0..<laneCount, id: \.self) { index in
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                    .fill(TimetableStyle.lane)
                    .frame(width: lane, height: layout.laneHeight)
                    .offset(x: laneX(index, lane: lane))
                if let midnight = layout.midnightY {
                    UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                        .fill(BSColor.Stage.glowBlue.opacity(0.09))
                        .frame(width: lane, height: layout.laneHeight - midnight)
                        .offset(x: laneX(index, lane: lane), y: midnight)
                }
            }

            ForEach(layout.hours, id: \.date) { mark in
                hourMark(mark, lanesWidth: laneX(laneCount, lane: lane) - Self.laneGap - Self.ruler)
            }

            ForEach(Array(layout.gaps.enumerated()), id: \.offset) { _, gap in
                changeover(height: gap.height)
                    .frame(width: lane, height: gap.height)
                    .offset(x: laneX(gap.laneIndex, lane: lane), y: gap.top)
                    .opacity(wantOnly ? 0 : 1)
            }

            ForEach(layout.cards) { card in
                let x = laneX(card.laneIndex, lane: lane)
                TimetableMatrixCard(
                    card: card,
                    width: lane,
                    avatarURL: avatarURL(card.artistName),
                    isGhost: wantOnly && !card.isInterested,
                    nowOffset: card.status == .live ? layout.nowY.map { $0 - card.top } : nil,
                    stageTint: TimetableStageLight.color(day.orderedStages[card.laneIndex].sortOrder),
                    timeZone: timeZone,
                    onToggle: {
                        if let performance = performances[card.id] { onToggleInterested(performance) }
                    }
                )
                .offset(x: x, y: card.top)
            }

            if let nowY = layout.nowY {
                nowLine(width: laneX(laneCount, lane: lane) - Self.laneGap - 46)
                    .offset(y: nowY - 9)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.35), value: wantOnly)
    }

    private func hourMark(_ mark: TimetableMatrixLayout.HourMark, lanesWidth: CGFloat) -> some View {
        let label = TimetableTimeFormat.time(mark.date, timeZone: timeZone)
        let lineColor = mark.isMidnight ? TimetableStyle.night.opacity(0.4) : Color.white.opacity(0.045)
        return ZStack(alignment: .topLeading) {
            Group {
                if mark.isMidnight {
                    Line().stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                } else {
                    Line().stroke(lineColor, lineWidth: 1)
                }
            }
            .frame(width: lanesWidth, height: 1)
            .offset(x: Self.ruler, y: mark.y)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Text(label.prefix(2)).foregroundStyle(mark.isMidnight ? TimetableStyle.night : TimetableStyle.muted))\(Text(label.dropFirst(2)).foregroundStyle(mark.isMidnight ? TimetableStyle.night : TimetableStyle.dim))")
                    .font(TimetableStyle.mono(11))
                if mark.isMidnight {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(TimetableStyle.night)
                }
            }
            .frame(width: 40, alignment: .trailing)
            .offset(y: mark.y - 8)
        }
        .allowsHitTesting(false)
    }

    private func changeover(height: CGFloat) -> some View {
        ZStack {
            Line(vertical: true)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: 1)
                .padding(.vertical, 10)
            if height > 96 {
                let label = BSLocalization.text("换场")
                Group {
                    if label.unicodeScalars.allSatisfy({ $0.value > 0x2E7F }) {
                        VStack(spacing: 6) {
                            ForEach(Array(label.enumerated()), id: \.offset) { _, character in
                                Text(String(character))
                            }
                        }
                    } else {
                        Text(label)
                            .fixedSize()
                            .rotationEffect(.degrees(90))
                            .frame(width: 14, height: 70)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TimetableStyle.dim.opacity(0.55))
                .padding(.vertical, 8)
                .background(TimetableStyle.lane)
            }
        }
        .allowsHitTesting(false)
    }

    private func nowLine(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(TimetableStyle.now)
                .frame(width: width, height: 1.5)
                .shadow(color: TimetableStyle.now.opacity(0.75), radius: 5)
                .offset(x: 46)
            Text(TimetableTimeFormat.time(now, timeZone: timeZone))
                .font(TimetableStyle.mono(11, weight: .bold))
                .foregroundStyle(TimetableStyle.background)
                .frame(width: 40, height: 18)
                .background(Capsule().fill(TimetableStyle.now))
                .shadow(color: TimetableStyle.now.opacity(0.6), radius: 6)
                .offset(x: 2)
        }
        .frame(height: 18)
    }
}

/// Soft stage light falling from a lit stage header.
private struct TimetableStageBeam: View {
    let isLive: Bool
    let color: Color
    @State private var breathe = false

    var body: some View {
        EllipticalGradient(
            colors: [color.opacity(0.28), color.opacity(0.08), .clear],
            center: .top,
            startRadiusFraction: 0,
            endRadiusFraction: 0.78
        )
        .blendMode(.screen)
        .opacity(isLive ? (breathe ? 1 : 0.7) : 0.36)
        .allowsHitTesting(false)
        .onAppear {
            guard isLive else { return }
            withAnimation(.easeInOut(duration: 2.75).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

private struct Line: Shape {
    var vertical = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if vertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
