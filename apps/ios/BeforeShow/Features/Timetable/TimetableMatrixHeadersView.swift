import SwiftUI

/// Owns the continuous scroll lighting updates without rebuilding the timeline.
struct TimetableMatrixHeadersView: View {
    let stages: [TimetableStage]
    let lane: CGFloat
    let layout: TimetableMatrixLayout
    let viewport: TimetableMatrixViewport
    let showsAddStage: Bool
    let onAddPerformance: (TimetableStage, Date?) -> Void
    let onRenameStage: (TimetableStage, String) -> Void
    let onManage: () -> Void

    private static let capHeight = TimetableStyle.matrixHeaderHeight
    private static let addStageWidth = TimetableStyle.matrixAddStageWidth

    @State private var editingStageID: UUID?
    @State private var draftStageName = ""
    @FocusState private var focusedStageID: UUID?

    private func laneX(_ index: Int, lane: CGFloat) -> CGFloat {
        TimetableStyle.matrixRulerWidth + CGFloat(index) * (lane + TimetableStyle.matrixLaneGap)
    }

    var body: some View {
        let progress = viewport.headerProgress
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
                    progress: progress
                )
                .offset(x: x, y: 0)
            }

            // "+ 舞台" top button
            if showsAddStage {
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

            // Pinned corner cover above ruler column
            TimetableMatrixCornerCover(viewport: viewport, progress: progress)
                .zIndex(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottom) {
                TimetableStyle.background
                if progress > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(TimetableMatrixCornerCover.dividerOpacity(progress)))
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
        progress: CGFloat
    ) -> some View {
        let isLive = activity == .live
        let idleProgress = min(1.0, progress * TimetableMatrixViewport.headerProgressDistance / 240.0)

        return HStack(spacing: 6) {
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
            if editingStageID == stage.id {
                TextField(BSLocalization.text("舞台名称"), text: $draftStageName)
                    .font(.system(size: 13, weight: .bold))
                    .textFieldStyle(.plain)
                    .focused($focusedStageID, equals: stage.id)
                    .submitLabel(.done)
                    .onSubmit { commitRename(stage) }
                    .onChange(of: focusedStageID) { _, focused in
                        if focused != stage.id && editingStageID == stage.id {
                            commitRename(stage)
                        }
                    }
            } else {
                Text(displayName(stage))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(
                        isLive
                            ? TimetableStyle.foreground
                            : Color.white.opacity(0.60 + idleProgress * 0.35)
                    )
            }
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
                progress: progress,
                lane: lane
            )
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                draftStageName = stage.name
                editingStageID = stage.id
                focusedStageID = stage.id
            } label: {
                Label(BSLocalization.text("重命名舞台"), systemImage: "pencil")
            }
            Button {
                onAddPerformance(stage, nil)
            } label: {
                Label(BSLocalization.text("在此舞台添加演出"), systemImage: "plus")
            }
            Button(action: onManage) {
                Label(BSLocalization.text("管理天数与舞台"), systemImage: "slider.horizontal.3")
            }
        }
    }

    /// A lone stage that was never named reads as plain "舞台" instead of "舞台 1".
    private func displayName(_ stage: TimetableStage) -> String {
        stages.count == 1 && stage.name == BSLocalization.format("舞台 %d", 1) ? BSLocalization.text("舞台") : stage.name
    }

    private func commitRename(_ stage: TimetableStage) {
        let name = draftStageName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != stage.name {
            onRenameStage(stage, name)
        }
        focusedStageID = nil
        editingStageID = nil
    }
}


/// Pinned corner cover above the ruler column. The only header piece that follows
/// horizontal scrolling frame by frame, so it stays a tiny view of its own.
private struct TimetableMatrixCornerCover: View {
    let viewport: TimetableMatrixViewport
    let progress: CGFloat

    static func dividerOpacity(_ progress: CGFloat) -> Double {
        0.08 * min(1, progress * TimetableMatrixViewport.headerProgressDistance / 200)
    }

    var body: some View {
        let scrollOffsetX = viewport.scrollOffsetX
        let edge = min(1, scrollOffsetX / 20)
        ZStack(alignment: .trailing) {
            TimetableStyle.background
                .overlay(alignment: .bottom) {
                    if progress > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(Self.dividerOpacity(progress)))
                            .frame(height: 0.5)
                    }
                }
            if scrollOffsetX > 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.12 * edge))
                    .frame(width: 0.5)
            }
        }
        .frame(width: TimetableStyle.matrixRulerWidth, height: TimetableStyle.matrixHeaderHeight)
        .overlay(alignment: .trailing) {
            TimetableMatrixEdgeShadow(opacity: scrollOffsetX > 1 ? 0.35 * edge : 0)
        }
        .offset(x: max(0, scrollOffsetX), y: 0)
        .contentShape(Rectangle())
    }
}

/// Soft shadow cast to the right of a pinned column, drawn as a gradient strip
/// instead of `.shadow` so scrolling never re-renders a blurred silhouette.
struct TimetableMatrixEdgeShadow: View {
    let opacity: Double

    var body: some View {
        LinearGradient(colors: [Color.black.opacity(opacity), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 7)
            .offset(x: 7)
            .allowsHitTesting(false)
    }
}

/// Ambient theatrical stage lighting for sticky stage header caps.
/// Idle headers carry a standby haze that deepens as the timeline scrolls; breathing
/// only animates opacity, and scroll depth arrives in coarse steps.
private struct TimetableStageHeaderAtmosphere: View {
    let tint: Color
    let activity: TimetableMatrixLayout.Activity
    let index: Int
    let progress: CGFloat
    let lane: CGFloat

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { activity == .live }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Base lane pillar cap
            TimetableStyle.lane

            // 2. Ambient Stage Color Wash (无演出时带柔和底色，随滑动距离慢慢加深)
            ambientWash
                .opacity(breathe ? 1 : (isLive ? 0.75 : 0.55))

            // 3. Downward Spotlight Cone / Origin Flare
            spotlightFlare
                .opacity(breathe || isLive ? 1 : 0.78)

            // 4. Subtle Top Truss Highlight (顶边高光)
            topTrussHighlight

            // 5. Bottom Stage Light / Laser Edge (连接下方舞台立柱光束的底边光条)
            bottomEdge
                .opacity(isLive && !breathe ? 0.79 : 1)
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

    private var ambientWash: some View {
        let topOpacity = isLive ? 0.16 : 0.08 + progress * 0.08
        let bottomOpacity = isLive ? 0.28 : 0.12 + progress * 0.14
        return LinearGradient(
            stops: [
                .init(color: tint.opacity(topOpacity), location: 0),
                .init(color: tint.opacity(bottomOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var spotlightFlare: some View {
        let flareOpacity = isLive ? 0.32 : 0.13 + progress * 0.18
        return RadialGradient(
            colors: [
                tint.opacity(flareOpacity),
                tint.opacity(flareOpacity * 0.45),
                .clear
            ],
            center: .bottom,
            startRadius: 0,
            endRadius: max(lane * 0.70, 48)
        )
    }

    private var topTrussHighlight: some View {
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

    private var bottomEdge: some View {
        let edgeOpacity = isLive ? 0.70 : min(0.70, 0.22 + progress * 0.38)
        let edgeHeight: CGFloat = isLive ? 1.5 : 1.0 + progress * 0.5
        let glowHeight = edgeHeight + 2 * (2.5 + progress * 2.0)
        return ZStack {
            // Glow under the edge line, standing in for a blurred shadow.
            LinearGradient(
                colors: [.clear, tint.opacity(edgeOpacity * 0.45), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: glowHeight)
            Rectangle()
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
        }
        .frame(height: glowHeight)
        .offset(y: glowHeight / 2 - edgeHeight / 2)
    }
}
