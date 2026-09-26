import SwiftData
import SwiftUI
import UIKit

/// Listen keeps the same dark stage language as Current / Footprints, but the
/// distant room light belongs to the Current Show instead of a fixed palette.
/// The player has its own disc-bound halo (see `ListeningPlayerAmbientHalo`), so
/// changing artists does not repaint the whole page.
struct ListeningStageBackground: View {
    let artworkURL: URL?
    let phase: ListeningAtmospherePhase
    private var isPlaying: Bool { phase == .playing }

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
                    } else {
                        fallbackStageGlows(in: geometry)
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

    @ViewBuilder
    private func fallbackStageGlows(in geometry: GeometryProxy) -> some View {
        listeningGlow(color: phase.color.opacity(phase.opacity * BSListeningTokens.roomLightOpacity))
            .frame(width: geometry.size.width * 1.4, height: geometry.size.height * 0.72)
            .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.60)
            .animation(.easeInOut(duration: BSListeningTokens.lightDuration), value: phase)
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

// MARK: - Root playback chrome

@MainActor @Observable final class ListeningPlaybackChromeStore {
    static let shared = ListeningPlaybackChromeStore()
    var room: ListeningRoomCoordinator?
    private init() {}
}
