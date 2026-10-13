import SwiftUI

/// Owns the continuous scroll lighting updates without rebuilding the timeline.
struct TimetableMatrixHeadersView: View {
    let stages: [TimetableStage]
    let lane: CGFloat
    let layout: TimetableMatrixLayout
    let viewport: TimetableMatrixViewport
    let onAddPerformance: (TimetableStage, Date?) -> Void
    let onManage: () -> Void

    private static let capHeight = TimetableStyle.matrixHeaderHeight
    private static let addStageWidth = TimetableStyle.matrixAddStageWidth

    private func laneX(_ index: Int, lane: CGFloat) -> CGFloat {
        TimetableStyle.matrixRulerWidth + CGFloat(index) * (lane + TimetableStyle.matrixLaneGap)
    }

    var body: some View {
        let scrollOffset = viewport.scrollOffsetY
        ZStack(alignment: .leading) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let x = laneX(index, lane: lane)
                let tint = TimetableStageLight.color(stage.sortOrder)
                stageHeaderMenu(
                    stage: stage,
                    lane: lane,
                    tint: tint,
                    activity: layout.activity.indices.contains(index) ? layout.activity[index] : .idle,
                    soonMinutes: layout.soonMinutes[index],
                    index: index,
                    scrollOffset: scrollOffset
                )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottom) {
                TimetableStyle.background
                if scrollOffset > 2 {
                    Rectangle()
                        .fill(Color.white.opacity(min(0.08, scrollOffset / 200.0 * 0.08)))
                        .frame(height: 0.5)
                }
            }
        }
    }

    /// Header light mirrors the lane: live glows energetically, while idle/soon
    /// carries a soft theatrical standby glow and beam flare that evolves smoothly
    /// as the user scrolls through the timeline.
    private func stageHeaderMenu(
        stage: TimetableStage,
        lane: CGFloat,
        tint: Color,
        activity: TimetableMatrixLayout.Activity,
        soonMinutes: Int?,
        index: Int,
        scrollOffset: CGFloat
    ) -> some View {
        let isLive = activity == .live
        let scrollDist = max(0, scrollOffset)
        let idleProgress = min(1.0, scrollDist / 240.0)

        return Menu {
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
                if isLive {
                    TimetableEqualizer(color: tint)
                } else {
                    ZStack {
                        // 现场舞台待机光晕：无演出时带轻微呼吸氛围，随滑动距离增强
                        TimetableStageLight.marker(stage.sortOrder)
                            .fill(tint)
                            .frame(width: 13, height: 13)
                            .blur(radius: 2.5)
                            .opacity(0.35 + idleProgress * 0.35)

                        TimetableStageLight.marker(stage.sortOrder)
                            .fill(tint)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(stage.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(
                        isLive
                            ? TimetableStyle.foreground
                            : Color.white.opacity(0.60 + idleProgress * 0.35)
                    )
                if activity == .soon, let soonMinutes {
                    Text(BSLocalization.format("%d 分钟后", soonMinutes))
                        .font(TimetableStyle.mono(10.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, BSSpacing.sm)
            .frame(width: lane, height: Self.capHeight)
            .background {
                TimetableStageHeaderAtmosphere(
                    tint: tint,
                    activity: activity,
                    index: index,
                    scrollOffset: scrollOffset,
                    lane: lane
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ambient theatrical stage lighting for sticky stage header caps.
/// When idle (no performance), presents gentle standby haze and moving-head beam flare that
/// responds smoothly to vertical scroll distance.
private struct TimetableStageHeaderAtmosphere: View {
    let tint: Color
    let activity: TimetableMatrixLayout.Activity
    let index: Int
    let scrollOffset: CGFloat
    let lane: CGFloat

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { activity == .live }

    var body: some View {
        let scrollDist = max(0, scrollOffset)
        let progress = min(1.0, scrollDist / 260.0)
        let dynamicPhase = scrollDist / 160.0
        let sweepDelta = sin(dynamicPhase + Double(index) * 1.3) * 14.0

        ZStack(alignment: .bottom) {
            // 1. Base lane pillar cap
            TimetableStyle.lane

            // 2. Ambient Stage Color Wash (无演出时带柔和底色，随滑动距离慢慢加深)
            ambientWash(progress: progress)

            // 3. Downward Spotlight Cone / Origin Flare (光束起点随滑动微调偏角)
            spotlightFlare(progress: progress, sweepDelta: sweepDelta)

            // 4. Subtle Top Truss Highlight (顶边高光)
            topTrussHighlight(progress: progress)

            // 5. Bottom Stage Light / Laser Edge (连接下方舞台立柱光束的底边光条)
            bottomEdge(progress: progress, dynamicPhase: dynamicPhase)
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: TimetableStyle.matrixLaneRadius,
            topTrailingRadius: TimetableStyle.matrixLaneRadius
        ))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: isLive ? 2.4 : 4.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func ambientWash(progress: CGFloat) -> some View {
        let breatheOffset = breathe ? 0.03 : -0.02
        let topOpacity: Double
        let bottomOpacity: Double

        if isLive {
            topOpacity = 0.12 + (breathe ? 0.04 : 0.0)
            bottomOpacity = 0.22 + (breathe ? 0.06 : 0.0)
        } else {
            // 没有演出时：静止时带柔和底色，滑动时随距离渐渐加深丰富
            topOpacity = max(0.02, 0.05 + progress * 0.08 + breatheOffset)
            bottomOpacity = max(0.04, 0.09 + progress * 0.14 + breatheOffset)
        }

        return LinearGradient(
            stops: [
                .init(color: tint.opacity(topOpacity), location: 0),
                .init(color: tint.opacity(bottomOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func spotlightFlare(progress: CGFloat, sweepDelta: Double) -> some View {
        let centerShift = reduceMotion ? 0.0 : (sweepDelta / max(lane, 1.0))
        let flareOpacity = isLive ? 0.32 : (0.10 + progress * 0.18 + (breathe ? 0.03 : 0.0))

        return RadialGradient(
            colors: [
                tint.opacity(flareOpacity),
                tint.opacity(flareOpacity * 0.45),
                .clear
            ],
            center: UnitPoint(x: 0.5 + centerShift, y: 1.0),
            startRadius: 0,
            endRadius: max(lane * 0.70, 48)
        )
        .blendMode(.screen)
    }

    private func topTrussHighlight(progress: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: TimetableStyle.matrixLaneRadius,
            topTrailingRadius: TimetableStyle.matrixLaneRadius
        )
        .stroke(
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.04 + progress * 0.05), location: 0),
                    .init(color: tint.opacity(0.12 + progress * 0.18), location: 0.5),
                    .init(color: Color.white.opacity(0.04 + progress * 0.05), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            lineWidth: 1
        )
    }

    private func bottomEdge(progress: CGFloat, dynamicPhase: CGFloat) -> some View {
        let edgeOpacity: Double
        let edgeHeight: CGFloat

        if isLive {
            edgeOpacity = breathe ? 0.70 : 0.55
            edgeHeight = 1.5
        } else {
            // 随滑动距离，底边从微光渐变到清晰的舞台激光切线
            let wave = reduceMotion ? 0.0 : sin(dynamicPhase + Double(index) * 1.5) * 0.06
            edgeOpacity = max(0.15, min(0.70, 0.22 + progress * 0.38 + wave))
            edgeHeight = 1.0 + progress * 0.5
        }

        return Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(edgeOpacity * 0.5), location: 0),
                        .init(color: tint.opacity(edgeOpacity), location: 0.5),
                        .init(color: tint.opacity(edgeOpacity * 0.5), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: edgeHeight)
            .shadow(color: tint.opacity(edgeOpacity * 0.6), radius: 2.5 + progress * 2.0, y: 0.5)
    }
}
