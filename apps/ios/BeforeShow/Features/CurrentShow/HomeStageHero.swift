import SwiftUI

/// The 当前 tab's stage: the poster on the LED wall, the rig warming up as the show gets
/// closer, the full programme once it starts, house lights after, a ghost light if postponed.
struct HomeStageHero: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    var reduceMotion = false
    /// How far the stage reaches up past its slot, behind the page header and status bar.
    var topExtension: CGFloat = 0
    /// Festival timetable live: the screens carry the acts instead of the poster.
    var screens: HomeStageScreens? = nil
    var livePhase: LiveModePhase? = nil
    var timetable: Timetable? = nil
    var avatars: TimetableArtistAvatarStore? = nil
    var onOpenTimetable: () -> Void = {}
    var onFocus: (UUID) -> Void = { _ in }

    @State private var lights = BSStageLights.fallback
    @State private var powered = false

    var body: some View {
        BSStageScene(colors: lights.map(\.color), lighting: lighting, powered: powered, height: 336 + topExtension) {
            if let screens, let timetable, let avatars {
                HomeStageScreenWall(
                    screens: screens,
                    timetable: timetable,
                    avatars: avatars,
                    mainSize: CGSize(width: Self.coverWidth, height: Self.coverWidth * 4 / 3),
                    onOpenTimetable: onOpenTimetable,
                    onFocus: onFocus
                )
            } else {
                HomeHeroStage(
                    show: show,
                    snapshot: snapshot,
                    coverWidth: Self.coverWidth,
                    reduceMotion: reduceMotion,
                    onStage: true
                )
            }
        }
        .padding(.top, -topExtension)
        // Keyed by show and by what the main screen shows: lights follow the poster, or the act on stage.
        .task(id: "\(show.id)|\(lightSource?.absoluteString ?? "")") {
            if let url = lightSource,
               let image = await ShowCoverImageCache.shared.image(from: url) {
                let picked = await BSStageLights.sampled(from: image)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) { lights = picked }
            } else {
                lights = BSStageLights.fallback
            }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08).delay(0.25)) { powered = true }
        }
    }

    private static let coverWidth: CGFloat = 156

    private var lightSource: URL? {
        if let screens, let timetable, let avatars {
            let perf = screens.main.performance
            return ArtistAvatarResolver.shared.displayURL(performanceID: perf.id, in: timetable, unlinked: avatars.url(for: perf.artistName))
        }
        return show.coverImageURL.flatMap(URL.init(string:))
    }

    private var lighting: BSStageLighting {
        switch livePhase {
        case .active?:
            // On stage the rig runs full; between sets one preset holds while the crew changes over.
            if case .live? = screens?.main { return .show(energy: 1) }
            return .show(energy: 0.15)
        case .upcoming?:
            return .show(energy: 0.4)
        case .dayEnded?, .fullyEnded?:
            return .house
        case nil:
            break
        }
        switch snapshot.phase {
        case .pre, .live:
            return .show(energy: HomeStageEnergy.energy(
                phase: snapshot.phase,
                start: snapshot.timeState.effectiveStartTime ?? show.effectiveDate,
                now: snapshot.now,
                calendar: show.timingCalendar()
            ))
        case .ended: return .house
        case .inactive: return snapshot.timeState.kind == .postponed ? .ghost : .dark
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
