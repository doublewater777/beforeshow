import SwiftUI

struct ListeningDiscStage: View {
    let disc: ListeningDisc?
    var angle: Double = 0
    let diameter: CGFloat

    var body: some View {
        ZStack {
            ListeningDiscArtwork(disc: disc)
                .rotationEffect(.degrees(angle))
                .overlay {
                    Circle().strokeBorder(ListeningStageTokens.metal, lineWidth: ListeningStageTokens.discRim)
                }
                .shadow(color: ListeningStageTokens.contactShadow, radius: BSSpacing.xs, y: BSSpacing.xs)

            if disc != nil {
                Circle()
                    .fill(ListeningStageTokens.metal)
                    .overlay(Circle().strokeBorder(.black.opacity(0.8), lineWidth: ListeningStageTokens.discRim))
                    .frame(width: diameter * ListeningStageTokens.hubFraction)
                    .shadow(color: ListeningStageTokens.contactShadow, radius: 1, y: 1)

                Image(decorative: "spindle_center")
                    .resizable().scaledToFit()
                    .scaleEffect(ListeningStageTokens.spindleAssetScale)
                    .frame(width: diameter * ListeningStageTokens.spindleFraction)
            }
        }
        .frame(width: diameter, height: diameter)
        .listeningFrame("stage")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(disc?.title ?? BSLocalization.text("无唱片"))
        .accessibilityIdentifier("listening.disc")
    }
}
