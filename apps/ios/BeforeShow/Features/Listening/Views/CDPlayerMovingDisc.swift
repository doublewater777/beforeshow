import SwiftUI

struct CDPlayerMovingDisc: View {
    let player: CDMechanism
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }
    private var motion: CDMotionDriver { player.motion }

    var body: some View {
        ZStack {
            ListeningDiscArtwork(disc: player.disc)
            Circle().strokeBorder(CDPlayerSurfaceTokens.discMetal, lineWidth: CDPlayerSurfaceTokens.ringWidth)
            Circle().fill(CDPlayerSurfaceTokens.discMetal)
                .frame(width: geometry.discDiameter * CDPlayerSurfaceTokens.discHubFraction)
            Circle().fill(.black)
                .frame(width: geometry.discDiameter * CDPlayerSurfaceTokens.discHoleFraction)
        }
        .frame(width: geometry.discDiameter, height: geometry.discDiameter)
        .clipShape(Circle())
        .rotationEffect(.degrees(motion.discAngle))
        .scaleEffect(motion.discScale.value)
        .scaleEffect(y: cos(geometry.tiltDegrees * .pi / 180))
        .shadow(color: .black.opacity(0.35), radius: BSSpacing.xs + motion.lift.value * BSSpacing.sm, y: BSSpacing.xs)
        .position(x: motion.discX.value, y: geometry.projectedY(motion.discY.value) - (motion.reducedMotion ? 0 : motion.lift.value * BSSpacing.roomy))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.disc?.title ?? "CD")
        .accessibilityIdentifier("listening.disc")
    }
}
