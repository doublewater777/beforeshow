import SwiftData
import SwiftUI
import UIKit

/// Listen keeps the same dark stage language as Current / Footprints. A single room
/// light takes the loaded disc's colour, falling back to the Current Show cover.
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

    private var lightColor: Color {
        discAmbientColor ?? showAmbientColor ?? phase.color.opacity(BSListeningTokens.roomLightOpacity)
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
                // One room light from above, falling across the shelf and the player.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                lightColor.opacity(isPlaying ? 0.48 : 0.34),
                                lightColor.opacity(isPlaying ? 0.20 : 0.13),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.8
                        )
                    )
                    .frame(width: geometry.size.width * 1.6, height: geometry.size.height * 0.78)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.26)
                    .blur(radius: 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)
            .animation(.easeInOut(duration: 0.8), value: lightColor)
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

// MARK: - Root playback chrome

@MainActor @Observable final class ListeningPlaybackChromeStore {
    static let shared = ListeningPlaybackChromeStore()
    var room: ListeningRoomCoordinator?
    private init() {}
}
