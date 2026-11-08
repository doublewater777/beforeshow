import SwiftUI

/// What the stage's LED screens carry once a festival timetable is live: the act on stage
/// in the middle, other live stages or the next act on the side screens.
struct HomeStageScreens: Equatable {
    enum Screen: Equatable {
        case live(LivePerformanceSnapshot)
        case next(LivePerformanceSnapshot)

        var performance: LivePerformanceSnapshot {
            switch self {
            case .live(let perf), .next(let perf): perf
            }
        }
    }

    let main: Screen
    let left: Screen?
    let right: Screen?

    /// nil keeps the poster on the wall (before the day's timetable, after the day is done).
    static func resolve(_ state: LiveModeState) -> HomeStageScreens? {
        let upcoming = state.upcomingPerformances.sorted { $0.startsAt < $1.startsAt }
        switch state.phase {
        case .active where !state.currentPerformances.isEmpty:
            let others = Array(state.currentPerformances.dropFirst())
            let next = upcoming.first.map(Screen.next)
            return HomeStageScreens(
                main: .live(state.currentPerformances[0]),
                left: others.first.map(Screen.live),
                right: others.count > 1 ? .live(others[1]) : next
            )
        case .active, .upcoming:
            guard let first = upcoming.first else { return nil }
            return HomeStageScreens(main: .next(first), left: nil, right: upcoming.dropFirst().first.map(Screen.next))
        case .dayEnded, .fullyEnded:
            return nil
        }
    }
}

/// The stage's centre screen with its side screens.
struct HomeStageScreenWall: View {
    let screens: HomeStageScreens
    let timetable: Timetable
    let avatars: TimetableArtistAvatarStore
    let mainSize: CGSize
    let onOpenTimetable: () -> Void
    let onFocus: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            side(screens.left)
            Button(action: onOpenTimetable) {
                mainScreen
            }
            .buttonStyle(.plain)
            .accessibilityHint(BSLocalization.text("完整时刻表"))
            side(screens.right)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: screens)
    }

    private var mainScreen: some View {
        let perf = screens.main.performance
        return ZStack(alignment: .bottomLeading) {
            HomeStageArtistImage(url: url(for: perf), name: perf.artistName)
            switch screens.main {
            case .live:
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                label("● LIVE · \(perf.stageName)", color: BSColor.Stage.live, size: 10)
                    .padding(9)
            case .next:
                Color.black.opacity(0.62)
                VStack(spacing: 6) {
                    Text(verbatim: "NEXT")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .tracking(5)
                        .foregroundStyle(BSColor.Stage.accent)
                    Text(perf.artistName)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    Text(clock(perf.startsAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: mainSize.width, height: mainSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay { BSLEDScanlines() }
        .id(perf.id)
        .transition(.opacity)
    }

    @ViewBuilder
    private func side(_ screen: HomeStageScreens.Screen?) -> some View {
        let size = CGSize(width: 58, height: 96)
        if let screen {
            let perf = screen.performance
            let content = ZStack(alignment: .bottomLeading) {
                HomeStageArtistImage(url: url(for: perf), name: perf.artistName)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    switch screen {
                    case .live: label("● \(perf.stageName)", color: BSColor.Stage.live, size: 7)
                    case .next: label("NEXT \(clock(perf.startsAt))", color: BSColor.Stage.accent, size: 7)
                    }
                    Text(perf.artistName)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(5)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay { BSLEDScanlines() }
            .id(perf.id)
            .transition(.opacity)

            if case .live = screen {
                Button { onFocus(perf.id) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint(BSLocalization.text("设为主现场"))
            } else {
                content
            }
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    private func label(_ text: String, color: Color, size: CGFloat) -> some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .bold))
            .tracking(size > 8 ? 1 : 0.3)
            .foregroundStyle(color)
            .lineLimit(1)
            .shadow(color: .black, radius: 3)
    }

    private func url(for perf: LivePerformanceSnapshot) -> URL? {
        ArtistAvatarResolver.shared.displayURL(performanceID: perf.id, in: timetable, unlinked: avatars.url(for: perf.artistName))
    }

    private func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// An artist photo filling a screen; the initial on a dark panel until one loads.
struct HomeStageArtistImage: View {
    let url: URL?
    let name: String
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                        Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                image = ShowCoverImageCache.shared.memoryImage(for: url)
                if image == nil {
                    let loaded = await ShowCoverImageCache.shared.image(from: url)
                    guard !Task.isCancelled else { return }
                    image = loaded
                }
            }
    }
}
