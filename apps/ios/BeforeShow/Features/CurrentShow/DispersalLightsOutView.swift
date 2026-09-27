import SwiftUI

struct DispersalLightsOutOverlay: View {
    let showName: String
    let ordinal: Int
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    var body: some View {
        Group {
            if reduceMotion {
                stage(progress: 0.5)
                    .saturation(0.2)
                    .brightness(-0.15)
            } else if let startedAt {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    let progress = DispersalLightsOutMotion.progress(
                        elapsed: elapsed,
                        duration: DispersalCeremonyPolicy.lightsOutDuration
                    )
                    stage(progress: progress)
                }
            } else {
                stage(progress: 0)
            }
        }
        .task {
            if reduceMotion {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(
                            DispersalCeremonyPolicy.reduceMotionLightsOutHoldDuration * 1_000_000_000
                        )
                    )
                    onComplete()
                } catch {
                    // 任务被取消时不推进下一段 presentation。
                }
                return
            }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(DispersalCeremonyPolicy.lightsOutTransitionLeadIn * 1_000_000_000)
                )
                startedAt = Date()
                try await Task.sleep(
                    nanoseconds: UInt64(DispersalCeremonyPolicy.lightsOutDuration * 1_000_000_000)
                )
                try await Task.sleep(
                    nanoseconds: UInt64(DispersalCeremonyPolicy.lightsOutBlackHoldDuration * 1_000_000_000)
                )
                onComplete()
            } catch {
                // 任务被取消(视图提前消失)时不回调 onComplete,后续交给父视图决定。
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(BSLocalization.format("散场，这是你的第 %lld 场现场", ordinal))
    }

    private func stage(progress: Double) -> some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            stageGlow(progress: progress)
            VStack(spacing: BSSpacing.md) {
                Text("散场")
                    .font(.system(size: 42, weight: .light))
                    .tracking(5)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.format("这是你的第 %lld 场现场", ordinal))
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.6)
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(.horizontal, BSSpacing.lg)
            .opacity(DispersalLightsOutMotion.titleOpacity(progress: progress))
        }
    }

    private func stageGlow(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack {
                beam(
                    color: BSColor.Stage.glowBlue,
                    x: proxy.size.width * 0.20,
                    width: 170 * proxy.size.width / 393,
                    height: proxy.size.height * 0.80,
                    startRotation: 16,
                    endRotation: 8,
                    peak: 0.90,
                    progress: progress
                )
                beam(
                    color: BSColor.Stage.accent,
                    x: proxy.size.width * 0.80,
                    width: 170 * proxy.size.width / 393,
                    height: proxy.size.height * 0.80,
                    startRotation: -16,
                    endRotation: -7,
                    peak: 0.85,
                    progress: progress
                )
                beam(
                    color: BSColor.Accent.violet,
                    x: proxy.size.width * 0.50,
                    width: 150 * proxy.size.width / 393,
                    height: proxy.size.height * 0.70,
                    startRotation: 0,
                    endRotation: 0,
                    peak: 0.70,
                    progress: progress
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    private func beam(
        color: Color,
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        startRotation: Double,
        endRotation: Double,
        peak: Double,
        progress: Double
    ) -> some View {
        let rotation = startRotation + (endRotation - startRotation) * progress
        let scaleY = 0.6 + 0.45 * progress
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.55), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.55
                )
            )
            .frame(width: width, height: height)
            .scaleEffect(x: 1, y: scaleY, anchor: .top)
            .rotationEffect(.degrees(rotation))
            .opacity(DispersalLightsOutMotion.beamOpacity(progress: progress, peak: peak))
            .position(x: x, y: height * 0.4)
            .blur(radius: 22)
    }
}
