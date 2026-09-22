import SwiftUI

struct ListeningStageSurface: View {
    let width: CGFloat
    @Environment(\.listeningSurfaceLight) private var surfaceLight

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(ListeningStageTokens.stageMetal)
            Image(decorative: "player_stage_surface")
                .resizable()
                .scaledToFit()
                .frame(width: width * ListeningStageTokens.surfaceWidthFraction)
                .opacity(ListeningStageTokens.surfaceOpacity)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.65),
                        .init(color: .clear, location: 0.86),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .offset(y: width * ListeningStageTokens.surfaceTopFraction)
            LinearGradient(colors: [surfaceLight.opacity(0.28), .clear, surfaceLight.opacity(0.13)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.screen)
        }
        .frame(width: width, height: width * ListeningStageTokens.surfaceWidthFraction * 4 / 3)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.13),
                .init(color: .white, location: 0.76),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.16),
                .init(color: .white, location: 0.84),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
