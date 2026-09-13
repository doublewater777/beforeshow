import SwiftUI
import UIKit

/// Show-bound room atmosphere for the Listen tab.
///
/// The show cover owns the distant stage light. The loaded disc owns only the
/// smaller bloom around the player so browsing artists does not repaint the
/// whole room. Playback adds a very slow local pulse; Reduce Motion keeps the
/// layer completely static.
struct ListeningAmbientBackground: View {
    let showCoverImageURL: String?
    let discArtworkURL: URL?
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAmbientColor: Color?
    @State private var discAmbientColor: Color?
    @State private var isBreathing = false

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
                    showBloom(in: geometry)
                    fallbackStageGlows(in: geometry)
                    discBloom(in: geometry)
                    discIridescence(in: geometry)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.18), location: 0.00),
                    .init(color: Color.black.opacity(0.10), location: 0.34),
                    .init(color: Color.black.opacity(0.22), location: 0.66),
                    .init(color: Color.black.opacity(0.62), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
        .task(id: showCoverImageURL) {
            showAmbientColor = await Self.loadAmbientColor(for: showCoverImageURL)
        }
        .task(id: discArtworkURL) {
            discAmbientColor = await Self.loadAmbientColor(for: discArtworkURL)
        }
        .onAppear(perform: updateBreathing)
        .onChange(of: isPlaying) { _, _ in updateBreathing() }
        .onChange(of: reduceMotion) { _, _ in updateBreathing() }
    }

    @ViewBuilder
    private func showBloom(in geometry: GeometryProxy) -> some View {
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
                .animation(.easeInOut(duration: 0.75), value: showAmbientColor)
        }
    }

    @ViewBuilder
    private func fallbackStageGlows(in geometry: GeometryProxy) -> some View {
        if showAmbientColor == nil {
            listeningGlow(color: Color(red: 0.69, green: 0.36, blue: 1.0).opacity(0.11))
                .frame(width: geometry.size.width * 0.86, height: geometry.size.height * 0.46)
                .position(x: geometry.size.width * 0.54, y: geometry.size.height * 0.92)

            listeningGlow(color: Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.07))
                .frame(width: geometry.size.width * 0.52, height: geometry.size.height * 0.34)
                .position(x: geometry.size.width * 0.16, y: geometry.size.height * 0.88)
        }
    }

    @ViewBuilder
    private func discBloom(in geometry: GeometryProxy) -> some View {
        if let discAmbientColor {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            discAmbientColor.opacity(0.32),
                            discAmbientColor.opacity(0.13),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: geometry.size.width * 0.46
                    )
                )
                .frame(
                    width: geometry.size.width * 0.92,
                    height: geometry.size.height * 0.34
                )
                .position(x: geometry.size.width * 0.50, y: geometry.size.height * 0.55)
                .blur(radius: 42)
                .scaleEffect(isBreathing ? 1.035 : 0.985)
                .opacity(isBreathing ? 1 : 0.88)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.7), value: discAmbientColor)
        }
    }

    @ViewBuilder
    private func discIridescence(in geometry: GeometryProxy) -> some View {
        if discArtworkURL != nil {
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
                    lineWidth: max(18, geometry.size.width * 0.065)
                )
                .frame(
                    width: geometry.size.width * 0.66,
                    height: geometry.size.height * 0.18
                )
                .position(x: geometry.size.width * 0.50, y: geometry.size.height * 0.55)
                .blur(radius: 34)
                .scaleEffect(isBreathing ? 1.025 : 0.99)
                .opacity(0.42)
        }
    }

    private func updateBreathing() {
        guard isPlaying, !reduceMotion, discArtworkURL != nil else {
            isBreathing = false
            return
        }
        isBreathing = false
        withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }

    private static func loadAmbientColor(for urlString: String?) async -> Color? {
        guard let urlString,
              let url = URL(string: urlString) else {
            return nil
        }
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

/// Bottom-of-screen stage glows matching the "当前" and "足迹" tabs.
/// Used while the Listen room has not bound its Current Show yet.
struct ListeningStageBackground: View {
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    listeningGlow(color: Color(red: 0.69, green: 0.36, blue: 1.0).opacity(0.18))
                        .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.58)
                        .position(x: geometry.size.width * 0.50, y: geometry.size.height * 1.02)

                    listeningGlow(color: Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.12))
                        .frame(width: geometry.size.width * 0.58, height: geometry.size.height * 0.40)
                        .position(x: geometry.size.width * 0.18, y: geometry.size.height * 0.92)

                    listeningGlow(color: Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.10))
                        .frame(width: geometry.size.width * 0.48, height: geometry.size.height * 0.34)
                        .position(x: geometry.size.width * 0.82, y: geometry.size.height * 0.92)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
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

    var body: some View {
        VStack(spacing: BSListeningTokens.songSpacing) {
            if room.mechanism.position == .seated, let track = room.track {
                VStack(spacing: BSSpacing.xs) {
                    Text(track.title)
                        .font(BSListeningTokens.songTitle)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text(track.artistName)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(2)
                    statusLine
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("listening.currentSong")
                .transition(.opacity)
            } else {
                statusLine
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .opacity(room.display.roomMode == .connecting ? 0 : 1)
                    .accessibilityHidden(room.display.roomMode == .connecting)
                    .accessibilityIdentifier("listening.playerGuidance")
            }

            if let recovery = player.recoveryAction {
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
        .frame(minHeight: BSListeningTokens.songHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.track?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: room.mechanism.position)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: player.phase)
    }

    private var statusLine: some View {
        Text(player.statusText)
            .font(BSListeningTokens.caption)
            .foregroundStyle(player.phase == .failed ? BSColor.Stage.danger : BSColor.Stage.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
