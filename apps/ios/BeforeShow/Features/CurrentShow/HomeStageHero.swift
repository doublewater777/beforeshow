import SwiftUI

/// The 当前 tab's stage: the poster on the LED wall, the rig warming up as the show gets
/// closer, the full programme once it starts, house lights after, a ghost light if postponed.
struct HomeStageHero: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    var isPlaybackActive = true
    var reduceMotion = false
    var isImportingDynamicCover = false
    var onChooseVideo: (() -> Void)? = nil
    /// How far the stage reaches up past its slot, behind the page header and status bar.
    var topExtension: CGFloat = 0

    @State private var lights = BSStageLights.fallback
    @State private var powered = false

    var body: some View {
        BSStageScene(colors: lights.map(\.color), lighting: lighting, powered: powered, height: 380 + topExtension) {
            HomeHeroStage(
                show: show,
                snapshot: snapshot,
                coverWidth: 168,
                isPlaybackActive: isPlaybackActive,
                reduceMotion: reduceMotion,
                isImportingDynamicCover: isImportingDynamicCover,
                onChooseVideo: onChooseVideo,
                opensDetail: true,
                onStage: true
            )
        }
        .padding(.top, -topExtension)
        // Keyed by show as well as cover: a different show never keeps the last one's colours.
        .task(id: "\(show.id)|\(show.coverImageURL ?? "")") {
            lights = BSStageLights.fallback
            if let link = show.coverImageURL, let url = URL(string: link),
               let image = await ShowCoverImageCache.shared.image(from: url) {
                let picked = await BSStageLights.sampled(from: image)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) { lights = picked }
            }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08).delay(0.25)) { powered = true }
        }
    }

    private var lighting: BSStageLighting {
        switch snapshot.phase {
        case .pre, .live:
            .show(energy: HomeStageEnergy.energy(
                phase: snapshot.phase,
                start: snapshot.timeState.effectiveStartTime ?? show.effectiveDate,
                now: snapshot.now,
                calendar: show.timingCalendar()
            ))
        case .ended: .house
        case .inactive: snapshot.timeState.kind == .postponed ? .ghost : .dark
        }
    }
}

/// How much of the light show runs while you wait: a still preset a week out, building
/// through the last days and hours, the full programme once the show starts.
enum HomeStageEnergy {
    static func energy(phase: HomeShowPhase, start: Date, now: Date, calendar: Calendar) -> Double {
        switch phase {
        case .live: return 1
        case .ended, .inactive: return 0
        case .pre:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
            switch days {
            case 7...: return 0.1
            case 3...6: return 0.35
            case 1...2: return 0.55
            default: return start.timeIntervalSince(now) > 3 * 3600 ? 0.7 : 0.85
            }
        }
    }
}
