import SwiftData
import SwiftUI
import UIKit

/// Listen keeps the same dark stage language as Current / Footprints, but the
/// distant room light belongs to the Current Show instead of a fixed palette.
/// The player has its own disc-bound halo (see `ListeningPlayerAmbientHalo`), so
/// changing artists does not repaint the whole page.
struct ListeningStageBackground: View {
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var showAmbientColor: Color?

    private var show: Show? {
        let id = CurrentShowSelectionStore.canonical(in: selections)?.selectedShowID
        return shows.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.018, blue: 0.025),
                    Color(red: 0.012, green: 0.012, blue: 0.018),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geometry in
                ZStack {
                    if let showAmbientColor {
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        showAmbientColor.opacity(0.54),
                                        showAmbientColor.opacity(0.22),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: geometry.size.width * 0.72
                                )
                            )
                            .frame(
                                width: geometry.size.width * 1.48,
                                height: geometry.size.height * 0.58
                            )
                            .position(x: geometry.size.width * 0.50, y: geometry.size.height * 0.07)
                            .blur(radius: 52)
                            .transition(.opacity)
                    } else {
                        fallbackStageGlows(in: geometry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 0.75), value: showAmbientColor)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.18), location: 0.00),
                    .init(color: Color.black.opacity(0.10), location: 0.34),
                    .init(color: Color.black.opacity(0.24), location: 0.68),
                    .init(color: Color.black.opacity(0.64), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
        .task(id: show?.coverImageURL) {
            showAmbientColor = await Self.loadAmbientColor(for: show?.coverImageURL)
        }
    }

    @ViewBuilder
    private func fallbackStageGlows(in geometry: GeometryProxy) -> some View {
        listeningGlow(color: Color(red: 0.69, green: 0.36, blue: 1.0).opacity(0.13))
            .frame(width: geometry.size.width * 0.88, height: geometry.size.height * 0.48)
            .position(x: geometry.size.width * 0.54, y: geometry.size.height * 0.94)

        listeningGlow(color: Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.08))
            .frame(width: geometry.size.width * 0.52, height: geometry.size.height * 0.34)
            .position(x: geometry.size.width * 0.16, y: geometry.size.height * 0.89)

        listeningGlow(color: Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.06))
            .frame(width: geometry.size.width * 0.44, height: geometry.size.height * 0.30)
            .position(x: geometry.size.width * 0.84, y: geometry.size.height * 0.90)
    }

    private static func loadAmbientColor(for urlString: String?) async -> Color? {
        guard let urlString,
              let url = URL(string: urlString),
              let image = await ShowCoverImageCache.shared.image(from: url),
              let ambient = CoverAmbientColor.uiColor(from: image) else {
            return nil
        }
        return Color(ambient)
    }
}

/// Local light emitted by the disc/player area. Album artwork contributes only
/// here, keeping the Current Show as the stable owner of the room atmosphere.
struct ListeningPlayerAmbientHalo: View {
    let artworkURL: URL?
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discAmbientColor: Color?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            if let discAmbientColor {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                discAmbientColor.opacity(0.34),
                                discAmbientColor.opacity(0.14),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 205
                        )
                    )
                    .blur(radius: 40)
                    .scaleEffect(isBreathing ? 1.04 : 0.985)
                    .opacity(isBreathing ? 1 : 0.88)
                    .transition(.opacity)
            }

            if artworkURL != nil {
                Ellipse()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.cyan.opacity(0.13),
                                Color.purple.opacity(0.10),
                                Color.pink.opacity(0.09),
                                Color.green.opacity(0.08),
                                Color.cyan.opacity(0.13)
                            ],
                            center: .center
                        ),
                        lineWidth: 28
                    )
                    .padding(28)
                    .blur(radius: 30)
                    .scaleEffect(isBreathing ? 1.025 : 0.99)
                    .opacity(0.38)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: discAmbientColor)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: artworkURL) {
            discAmbientColor = await Self.loadAmbientColor(for: artworkURL)
            updateBreathing()
        }
        .onAppear(perform: updateBreathing)
        .onChange(of: isPlaying) { _, _ in updateBreathing() }
        .onChange(of: reduceMotion) { _, _ in updateBreathing() }
    }

    private func updateBreathing() {
        guard isPlaying, !reduceMotion, artworkURL != nil else {
            isBreathing = false
            return
        }
        isBreathing = false
        withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }

    private static func loadAmbientColor(for url: URL?) async -> Color? {
        guard let url,
              let image = await ShowCoverImageCache.shared.image(from: url),
              let ambient = CoverAmbientColor.uiColor(from: image) else {
            return nil
        }
        return Color(ambient)
    }
}

private func listeningGlow(color: Color) -> some View {
    Ellipse()
        .fill(
            RadialGradient(
                colors: [color, color.opacity(0.55), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 230
            )
        )
        .blur(radius: 22)
}

struct ListeningCurrentSong: View {
    let room: ListeningRoomCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var player: ListeningPlayerPresentation { room.display.player }
    private var showsInlineGuidance: Bool {
        room.mechanism.position != .seated || room.track == nil
    }
    private var recovery: ListeningRecoveryAction? {
        player.recoveryAction ?? room.display.recoveryAction
    }

    var body: some View {
        VStack(spacing: BSListeningTokens.songSpacing) {
            if showsInlineGuidance {
                statusLine
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .opacity(room.display.roomMode == .connecting ? 0 : 1)
                    .accessibilityHidden(room.display.roomMode == .connecting)
                    .accessibilityIdentifier("listening.playerGuidance")
            }

            if let recovery {
                Button(recovery.title) {
                    room.performListeningRecovery(recovery)
                }
                .font(BSListeningTokens.captionMedium)
                .foregroundStyle(BSColor.Stage.accent)
                .frame(minHeight: BSLayout.minTouchTarget)
                .buttonStyle(BSListeningPressStyle(scale: 0.96))
                .accessibilityIdentifier("listening.playerRecovery")
            }
        }
        .frame(minHeight: showsInlineGuidance || recovery != nil ? BSListeningTokens.songHeight : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.track?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.mechanism.position)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: player.phase)
        .onAppear {
            ListeningPlaybackChromeStore.shared.room = room
        }
    }

    private var statusLine: some View {
        Text(player.statusText)
            .font(BSListeningTokens.caption)
            .foregroundStyle(player.phase == .failed ? BSColor.Stage.danger : BSColor.Stage.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Root playback chrome
// Kept in this already-targeted listening view source so the committed Xcode
// project remains buildable even when the generated project has not been refreshed.

@MainActor @Observable final class ListeningPlaybackChromeStore {
    static let shared = ListeningPlaybackChromeStore()
    var room: ListeningRoomCoordinator?
    private init() {}
}

enum ListeningBottomChromeMode: Equatable {
    case tabsOnly
    case fullPlayer
    case compactPlayer

    static func resolve(selectedTab: BeforeShowTab, hasLoadedDisc: Bool) -> Self {
        guard hasLoadedDisc else { return .tabsOnly }
        return selectedTab == .listen ? .fullPlayer : .compactPlayer
    }
}

struct ListeningBottomChrome: View {
    @Binding var selectedTab: BeforeShowTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerNamespace
    @State private var store = ListeningPlaybackChromeStore.shared
    @State private var frozenDiscAngle = 0.0
    @State private var spinAnchor = Date()

    private let spinDegreesPerSecond = 132.0
    private var room: ListeningRoomCoordinator? { store.room }
    private var hasLoadedDisc: Bool {
        guard let room else { return false }
        return room.mechanism.hasDisc && room.track != nil
    }
    private var isPlaying: Bool { room?.isPlaying == true }
    private var mode: ListeningBottomChromeMode {
        .resolve(selectedTab: selectedTab, hasLoadedDisc: hasLoadedDisc)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isPlaying)) { timeline in
            VStack(spacing: 7) {
                if mode == .fullPlayer, let room, let track = room.track {
                    ListeningFullMiniPlayer(
                        room: room,
                        track: track,
                        discAngle: discAngle(at: timeline.date),
                        namespace: playerNamespace
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ListeningMorphingTabBar(
                    selectedTab: $selectedTab,
                    room: room,
                    mode: mode,
                    discAngle: discAngle(at: timeline.date),
                    namespace: playerNamespace
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.90), value: mode)
        .onChange(of: isPlaying, initial: true) { wasPlaying, nowPlaying in
            let now = Date()
            if wasPlaying && !nowPlaying {
                frozenDiscAngle = runningDiscAngle(at: now)
            } else if !wasPlaying && nowPlaying {
                spinAnchor = now
            }
        }
        .onChange(of: reduceMotion) { wasReduced, isReduced in
            let now = Date()
            if !wasReduced && isReduced && isPlaying {
                frozenDiscAngle = runningDiscAngle(at: now)
            } else if wasReduced && !isReduced && isPlaying {
                spinAnchor = now
            }
        }
    }

    private func runningDiscAngle(at date: Date) -> Double {
        (frozenDiscAngle + date.timeIntervalSince(spinAnchor) * spinDegreesPerSecond)
            .truncatingRemainder(dividingBy: 360)
    }

    private func discAngle(at date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return frozenDiscAngle }
        return runningDiscAngle(at: date)
    }
}

private struct ListeningFullMiniPlayer: View {
    @Bindable var room: ListeningRoomCoordinator
    let track: ListeningDiscTrack
    let discAngle: Double
    let namespace: Namespace.ID

    private var trackNumber: String { String(format: "%02d", room.trackIndex + 1) }
    private var statusText: String { BSLocalization.text(room.isPlaying ? "播放中" : "暂停") }
    private var progress: Double? {
        guard let duration = track.duration, duration.isFinite, duration > 0 else { return nil }
        return min(max(room.elapsed / duration, 0), 1)
    }
    private var lidIsOpen: Bool {
        (room.mechanism.motion.lid.target ?? room.mechanism.motion.lid.value) > 0.5
    }

    var body: some View {
        HStack(spacing: 12) {
            ListeningMiniDisc(angle: discAngle, size: 46)
                .matchedGeometryEffect(id: "listeningMiniPlayer.disc", in: namespace)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("TR \(trackNumber) · \(track.artistName) · \(statusText)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                if let progress {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(LinearGradient(colors: [.cyan.opacity(0.9), .blue.opacity(0.75), .purple.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(3, proxy.size.width * progress))
                            }
                    }
                    .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { room.perform(.open) } label: {
                ListeningLidGlyph(isOpen: lidIsOpen)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(lidIsOpen ? "关闭 CD 盖" : "打开 CD 盖"))
            .accessibilityIdentifier("listening.miniPlayer.open")

            Button { room.perform(.playPause) } label: {
                Image(systemName: room.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.cyan.opacity(0.92))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(Color.cyan.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(room.isPlaying ? "暂停" : "播放"))
            .accessibilityIdentifier("listening.miniPlayer.playPause")
        }
        .padding(.horizontal, 12)
        .frame(height: 76)
        .background {
            ListeningPlayerSurface()
                .matchedGeometryEffect(id: "listeningMiniPlayer.surface", in: namespace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.miniPlayer.full")
    }
}

private struct ListeningMorphingTabBar: View {
    @Binding var selectedTab: BeforeShowTab
    let room: ListeningRoomCoordinator?
    let mode: ListeningBottomChromeMode
    let discAngle: Double
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            rootTab(.current)
            if mode == .compactPlayer, let room, let track = room.track {
                compactListenPlayer(room: room, track: track)
                    .frame(minWidth: 164, maxWidth: .infinity)
                    .layoutPriority(2)
            } else {
                rootTab(.listen)
            }
            rootTab(.footprints)
        }
        .padding(6)
        .frame(height: 66)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(Color.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1) }
        .shadow(color: .black.opacity(0.30), radius: 22, y: 10)
        .accessibilityIdentifier("root.customTabBar")
    }

    private func rootTab(_ tab: BeforeShowTab) -> some View {
        let selected = selectedTab == tab
        let compact = mode == .compactPlayer
        let showLabel = !compact || selected
        return Button { select(tab) } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.iconName).font(.system(size: 18, weight: .medium))
                if showLabel {
                    Text(tab.localizedTitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? Color.cyan.opacity(0.92) : Color.white.opacity(0.66))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.cyan.opacity(0.16), lineWidth: 1) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("root.tab.\(tab.id)")
    }

    private func compactListenPlayer(room: ListeningRoomCoordinator, track: ListeningDiscTrack) -> some View {
        HStack(spacing: 8) {
            Button { select(.listen) } label: {
                HStack(spacing: 8) {
                    ListeningMiniDisc(angle: discAngle, size: 34)
                        .matchedGeometryEffect(id: "listeningMiniPlayer.disc", in: namespace)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compactAccessibilityLabel(room: room, track: track))
            .accessibilityHint(BSLocalization.text("返回听"))

            Button { room.perform(.playPause) } label: {
                Image(systemName: room.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.cyan.opacity(0.92))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.busy)
            .accessibilityLabel(BSLocalization.text(room.isPlaying ? "暂停" : "播放"))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background {
            ListeningPlayerSurface()
                .matchedGeometryEffect(id: "listeningMiniPlayer.surface", in: namespace)
        }
        .accessibilityIdentifier("listening.miniPlayer.compact")
    }

    private func compactAccessibilityLabel(room: ListeningRoomCoordinator, track: ListeningDiscTrack) -> String {
        let state = BSLocalization.text(room.isPlaying ? "正在播放" : "已暂停")
        return "\(BeforeShowTab.listen.localizedTitle)，\(state) \(track.title)，\(track.artistName)"
    }

    private func select(_ tab: BeforeShowTab) {
        guard selectedTab != tab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.90)) { selectedTab = tab }
        }
    }
}

private struct ListeningMiniDisc: View {
    let angle: Double
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [Color.cyan.opacity(0.78), Color.purple.opacity(0.72), Color.yellow.opacity(0.60), Color.mint.opacity(0.68), Color.blue.opacity(0.74), Color.cyan.opacity(0.78)], center: .center))
            Circle().stroke(Color.white.opacity(0.34), lineWidth: 0.7).padding(size * 0.12)
            Circle().fill(Color.black.opacity(0.82)).frame(width: size * 0.24, height: size * 0.24)
            Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.6).frame(width: size * 0.14, height: size * 0.14)
            Capsule().fill(Color.white.opacity(0.32)).frame(width: size * 0.28, height: 1).offset(x: size * 0.20)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .shadow(color: Color.cyan.opacity(0.14), radius: 10)
        .accessibilityHidden(true)
    }
}

private struct ListeningPlayerSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(LinearGradient(colors: [Color.cyan.opacity(0.10), Color.clear, Color.purple.opacity(0.10)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.cyan.opacity(0.36), Color.white.opacity(0.08), Color.purple.opacity(0.28)], startPoint: .leading, endPoint: .trailing), lineWidth: 1)
            }
            .shadow(color: Color.cyan.opacity(0.08), radius: 20, y: 8)
    }
}

private struct ListeningLidGlyph: View {
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 1.4)
                .frame(width: 18, height: 10)
                .offset(y: 4)
            Circle().stroke(Color.cyan.opacity(0.68), lineWidth: 1.1).frame(width: 6, height: 6).offset(y: 4)
            Capsule()
                .fill(Color.white.opacity(0.76))
                .frame(width: 18, height: 1.5)
                .rotationEffect(.degrees(isOpen ? -22 : 0), anchor: .leading)
                .offset(x: isOpen ? 1 : 0, y: isOpen ? -4 : -2)
        }
        .foregroundStyle(Color.white.opacity(0.80))
        .background(Color.white.opacity(0.045), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.86), value: isOpen)
    }
}
