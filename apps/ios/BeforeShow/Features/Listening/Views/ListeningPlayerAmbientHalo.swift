import SwiftUI

struct ListeningPlayerAmbientHalo: View {
    let artworkURL: URL?
    let phase: ListeningAtmospherePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discAmbientColor: Color?

    private var light: Color {
        phase == .playing ? discAmbientColor ?? phase.color : phase.color
    }

    var body: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [light, light.opacity(0.45), .clear],
                center: .center,
                startRadius: 0,
                endRadius: BSListeningTokens.haloRadius
            ))
            .blur(radius: BSListeningTokens.haloBlur)
            .opacity(phase.opacity)
            .scaleEffect(reduceMotion ? 1 : phase.scale)
            .animation(.easeInOut(duration: BSListeningTokens.lightDuration), value: phase)
            .animation(.easeInOut(duration: BSListeningTokens.lightDuration), value: discAmbientColor)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: artworkURL) {
                discAmbientColor = nil
                guard let artworkURL,
                      let image = await ShowCoverImageCache.shared.image(from: artworkURL),
                      !Task.isCancelled,
                      let color = CoverAmbientColor.uiColor(from: image) else { return }
                discAmbientColor = Color(color)
            }
    }
}
