import SwiftData
import SwiftUI
import UIKit

/// Listen keeps the same dark stage language as Current / Footprints, but the
/// distant room light belongs to the Current Show instead of a fixed palette.
/// The player has its own disc-bound halo (see `ListeningPlayerAmbientHalo`), so
/// changing artists does not repaint the whole page.
struct ListeningStageBackground: View {
    let artworkURL: URL?
    let isPlaying: Bool

    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var showAmbientColor: Color?
    @State private var discAmbientColor: Color?

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
                                        showAmbientColor.opacity(0.42),
                                        showAmbientColor.opacity(0.16),
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
                            .blur(radius: 56)
                            .transition(.opacity)
                    }

                    if let discAmbientColor {
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        discAmbientColor.opacity(isPlaying ? 0.50 : 0.34),
                                        discAmbientColor.opacity(isPlaying ? 0.24 : 0.15),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: geometry.size.width * 0.82
                                )
                            )
                            .frame(
                                width: geometry.size.width * 1.70,
                                height: geometry.size.height * 0.72
                            )
                            .position(x: geometry.size.width * 0.50, y: geometry.size.height * 0.34)
                            .blur(radius: isPlaying ? 68 : 58)
                            .transition(.opacity)
                    }
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 0.75), value: showAmbientColor)
            .animation(.easeInOut(duration: 0.80), value: discAmbientColor)
            .animation(.easeInOut(duration: 0.55), value: isPlaying)

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
        .task(id: artworkURL) {
            discAmbientColor = await Self.loadAmbientColor(for: artworkURL)
        }
    }

    private static func loadAmbientColor(for urlString: String?) async -> Color? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return await loadAmbientColor(for: url)
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
                                discAmbientColor.opacity(isPlaying ? 0.46 : 0.34),
                                discAmbientColor.opacity(isPlaying ? 0.19 : 0.13),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 205
                        )
                    )
                    .blur(radius: 34)
                    .scaleEffect(isBreathing ? 1.04 : 0.985)
                    .opacity(isBreathing ? 1 : 0.88)
                    .transition(.opacity)
            }

        }
        .compositingGroup()
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

struct ListeningCurrentSong: View {
    let room: ListeningRoomCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var player: ListeningPlayerPresentation { room.display.player }
    private var showsInlineGuidance: Bool {
        room.mechanism.position != .seated || room.track == nil
    }
    private var recovery: ListeningRecoveryAction? {
        guard player.recoveryAction == .retryPlayback else { return nil }
        return .retryPlayback
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

@MainActor @Observable final class ListeningPlaybackChromeStore {
    static let shared = ListeningPlaybackChromeStore()
    var room: ListeningRoomCoordinator?
    private init() {}
}
