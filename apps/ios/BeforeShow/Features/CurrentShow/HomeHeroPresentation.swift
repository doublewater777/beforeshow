import SwiftUI

// MARK: - Home hero presentation
//
// One module owns the phase+timeState pair that every hero helper used to thread
// as two arguments. Callers pass a single `HomeHeroSnapshot`; HomeShowPhase stays
// in Shared for widget/countdown reuse, but the home poster derives it here.

/// Derivation surface for the home poster: time-state copy + phase, from one `now`.
struct HomeHeroSnapshot: Equatable {
    let timeState: CurrentShowTimeState
    let phase: HomeShowPhase
    let now: Date

    init(show: Show, now: Date, calendar: Calendar = .current) {
        self.now = now
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        self.timeState = state
        self.phase = HomeShowPhase(timeState: state, now: now)
    }

    init(timeState: CurrentShowTimeState, now: Date) {
        self.now = now
        self.timeState = timeState
        self.phase = HomeShowPhase(timeState: timeState, now: now)
    }
}

/// 3:4 cover poster on the home stage.
struct HomeHeroStage: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let coverWidth: CGFloat
    var reduceMotion: Bool = false
    @State private var glowBreathing = false
    /// Hung as the LED wall of the stage: square corners, scanlines, the stage does the glow.
    var onStage = false

    private var coverHeight: CGFloat { coverWidth * 4.0 / 3.0 }
    private var cornerRadius: CGFloat { onStage ? 2 : 26 }
    private var phase: HomeShowPhase { snapshot.phase }

    var body: some View {
        heroVisual(width: coverWidth, height: coverHeight)
        .accessibilityAddTraits(.isImage)
        .frame(width: coverWidth, height: coverHeight)
    }

    private func heroVisual(width: CGFloat, height: CGFloat) -> some View {
        ShowCoverImageView(
            urlString: show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            alignment: .center,
            enforcesAspectRatio: false,
            cornerRadius: cornerRadius,
            restoresPersistedImageOnFirstFrame: true
        )
        .id(show.id)
        .frame(width: width, height: height)
        .saturation(phase == .inactive ? 0.35 : (phase == .ended ? 0.72 : 1.0))
        .brightness(phase == .inactive ? -0.18 : (phase == .ended ? -0.05 : 0))
        // ShowCoverImageView 先按自身比例布局；外层改成固定 3:4 尺寸后必须再次裁切，
        // 否则图片会越过 352pt 卡片边界，让海报看起来横向错位。
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay { if onStage { BSLEDScanlines() } }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(onStage ? 0 : 0.55), radius: 30, y: 15)
        .background {
            if phase == .pre || phase == .live, !reduceMotion, !onStage {
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        RadialGradient(
                            colors: [
                                BSColor.Stage.accent.opacity(glowBreathing ? 0.25 : 0.10),
                                .clear
                            ],
                            center: .center,
                            startRadius: coverWidth * 0.3,
                            endRadius: coverWidth * 0.75
                        )
                    )
                    .blur(radius: 30)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 3.0)
                            .repeatForever(autoreverses: true)
                        ) {
                            glowBreathing = true
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    /// 导入耗时不可预估(图库可能要先下载 iCloud 原件),所以用不确定进度 + 一句说明。
}
