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
        screen(screens.main, size: mainSize, compact: false)
    }

    @ViewBuilder
    private func side(_ screen: HomeStageScreens.Screen?) -> some View {
        let size = CGSize(width: 58, height: 96)
        if let screen {
            if case .live = screen {
                Button { onFocus(screen.performance.id) } label: { self.screen(screen, size: size, compact: true) }
                    .buttonStyle(.plain)
                    .accessibilityHint(BSLocalization.text("设为主现场"))
            } else {
                self.screen(screen, size: size, compact: true)
            }
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    /// A 3:4 screen: the square artist photo uncropped on top, a caption strip under it.
    private func screen(_ screen: HomeStageScreens.Screen, size: CGSize, compact: Bool) -> some View {
        let perf = screen.performance
        return VStack(alignment: .leading, spacing: 0) {
            HomeStageArtistImage(url: url(for: perf), name: perf.artistName)
                .frame(width: size.width, height: size.width)
            VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                switch screen {
                case .live:
                    label(compact ? "● \(perf.stageName)" : "● LIVE · \(perf.stageName)", color: BSColor.Stage.live, size: compact ? 7 : 10)
                case .next:
                    label(compact ? "NEXT \(clock(perf.startsAt))" : "NEXT · \(clock(perf.startsAt))", color: BSColor.Stage.accent, size: compact ? 7 : 10)
                }
                Text(perf.artistName)
                    .font(.system(size: compact ? 8.5 : 15, weight: compact ? .bold : .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, compact ? 4 : 9)
            .padding(.top, compact ? 4 : 7)
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .id(perf.id)
        .transition(.opacity)
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
