import SwiftUI

struct ListeningDiscStage: View {
    let disc: ListeningDisc?
    var angle: Double = 0
    let diameter: CGFloat

    var body: some View {
        ZStack {
            ListeningDiscArtwork(disc: disc)
                .rotationEffect(.degrees(angle))
            if disc != nil {
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
