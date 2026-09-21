import SwiftUI

/// Two faces on a single plane. The same fixed hinge drives every intermediate pose.
struct CDPlayerLidSurface: View {
    let player: CDMechanism
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }
    private var cosine: Double {
        cos((geometry.tiltDegrees + player.motion.lid.value * geometry.maximumOpening) * .pi / 180)
    }

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.04))
            Image(decorative: player.configuration.assets.lidGlass)
                .resizable().clipShape(Circle())
                .opacity(cosine >= 0 ? 1 : 0)
            Image(decorative: player.configuration.assets.lidInner)
                .resizable().clipShape(Circle())
                .brightness(-0.25)
                .opacity(cosine < 0 ? 1 : 0)
                .scaleEffect(y: -1)
            Circle().strokeBorder(CDPlayerSurfaceTokens.rim, lineWidth: CDPlayerSurfaceTokens.ringWidth)
            Circle().strokeBorder(.white.opacity(0.13), lineWidth: BSListeningTokens.hairline)
                .padding(BSSpacing.xs)
        }
        .frame(width: geometry.lid.width, height: geometry.lid.height)
        .scaleEffect(y: cosine, anchor: .top)
        .position(x: geometry.lid.midX, y: geometry.hingeY + geometry.lid.height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
