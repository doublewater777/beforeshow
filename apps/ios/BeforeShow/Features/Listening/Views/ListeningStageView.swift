import SwiftUI

struct ListeningStageView: View {
    let room: ListeningRoomCoordinator
    let width: CGFloat

    var body: some View {
        VStack(spacing: BSSpacing.roomy) {
            ListeningDiscStage(
                disc: room.mechanism.disc,
                angle: room.mechanism.motion.discAngle,
                diameter: width * ListeningStageTokens.discWidthFraction
            )
            .background {
                ListeningPlayerAmbientHalo(
                    artworkURL: room.mechanism.disc?.artworkURL,
                    isPlaying: room.isPlaying
                )
            }
            ListeningTrackInformation(room: room)
                .padding(.horizontal, BSSpacing.roomy)
            ListeningTransportControls(room: room)
        }
        .padding(.top, BSSpacing.md)
        .padding(.bottom, BSSpacing.roomy)
        .frame(width: width)
        .background(alignment: .top) { ListeningStageSurface(width: width) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.stage")
    }
}
