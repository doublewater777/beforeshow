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
