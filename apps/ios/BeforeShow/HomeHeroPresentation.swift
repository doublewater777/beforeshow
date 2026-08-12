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

/// 3:4 cover poster on the home stage: glow and cover artwork.
struct HomeHeroStage: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let coverWidth: CGFloat
    var isPlaybackActive = true
    var reduceMotion: Bool = false
    var onChooseVideo: (() -> Void)? = nil

    private var coverHeight: CGFloat { coverWidth * 4.0 / 3.0 }
    private var phase: HomeShowPhase { snapshot.phase }

    var body: some View {
        heroVisual(width: coverWidth, height: coverHeight)
        .accessibilityAddTraits(.isImage)
        .frame(width: coverWidth, height: coverHeight)
    }

    private func heroVisual(width: CGFloat, height: CGFloat) -> some View {
        DynamicCoverFlipView(
            showID: show.id,
            dynamicCover: show.dynamicCover,
            width: width,
            height: height,
            isPlaybackActive: isPlaybackActive && phase != .inactive,
            reduceMotion: reduceMotion,
            onChooseVideo: onChooseVideo,
            accessibilityName: show.name
        ) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                alignment: .center,
                enforcesAspectRatio: false,
                cornerRadius: 26
            )
        }
        .frame(width: width, height: height)
        .saturation(phase == .inactive ? 0.35 : (phase == .ended ? 0.72 : 1.0))
        .brightness(phase == .inactive ? -0.18 : (phase == .ended ? -0.05 : 0))
        .overlay {
            heroGlow(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        // ShowCoverImageView 先按自身比例布局；外层改成固定 3:4 尺寸后必须再次裁切，
        // 否则图片会越过 352pt 卡片边界，让海报看起来横向错位。
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 15)
    }

    /// hero-glow:蓝 / 紫两束舞台侧光,screen 混合;live 全开,ended 收半,inactive 几近熄灭。
    private func heroGlow(width: CGFloat, height: CGFloat) -> some View {
        let opacity: Double
        switch phase {
        case .live: opacity = 1.0
        case .pre: opacity = 0.92
        case .ended: opacity = 0.45
        case .inactive: opacity = 0.18
        }
        return ZStack {
            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Stage.glowBlue.opacity(0.30), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.26
                ))
                .frame(width: width * 0.52, height: height * 0.34)
                .position(x: width * 0.16, y: height * 0.70)

            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Stage.prepare.opacity(0.28), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.23
                ))
                .frame(width: width * 0.46, height: height * 0.28)
                .position(x: width * 0.88, y: height * 0.62)
        }
        .blendMode(.screen)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

}
