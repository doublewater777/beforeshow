import SwiftUI

struct ListeningStageView: View {
    let room: ListeningRoomCoordinator
    let width: CGFloat
    @State private var surfaceLight: Color = .clear

    private var lightingArtworkURL: URL? {
        room.mechanism.disc?.artworkURL ?? room.mechanism.disc?.tracks.compactMap(\.artworkURL).first
    }

    var body: some View {
        VStack(spacing: BSSpacing.roomy) {
            ListeningDiscStage(
                disc: room.mechanism.disc,
                angle: room.mechanism.motion.discAngle,
                diameter: width * ListeningStageTokens.discWidthFraction
            )
            .background {
                ListeningPlayerAmbientHalo(
                    artworkURL: lightingArtworkURL,
                    isPlaying: room.isPlaying
                )
            }
            ListeningTrackInformation(room: room)
                .padding(.horizontal, ListeningStageTokens.informationInset)
            ListeningTransportControls(room: room)
                .padding(.top, BSSpacing.sm)
        }
        .padding(.top, BSSpacing.md)
        .padding(.bottom, BSSpacing.roomy)
        .frame(width: width)
        .background(alignment: .top) { ListeningStageSurface(width: width) }
        .environment(\.listeningSurfaceLight, surfaceLight)
        .task(id: lightingArtworkURL) {
            guard let url = lightingArtworkURL,
                  let image = await ShowCoverImageCache.shared.image(from: url),
                  let color = CoverAmbientColor.uiColor(from: image), !Task.isCancelled else {
                if !Task.isCancelled { surfaceLight = .clear }
                return
            }
            surfaceLight = Color(color)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.stage")
    }
}
