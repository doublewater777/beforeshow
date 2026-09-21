import SwiftUI

struct ListeningStageSurface: View {
    let width: CGFloat

    var body: some View {
        Image(decorative: "player_stage_surface")
            .resizable()
            .scaledToFit()
            .frame(width: width * ListeningStageTokens.surfaceWidthFraction)
            .opacity(ListeningStageTokens.surfaceOpacity)
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.28),
                    .init(color: .white, location: 0.70),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.18),
                    .init(color: .white, location: 0.82),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
            .offset(y: width * ListeningStageTokens.surfaceTopFraction)
            .frame(width: width, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
