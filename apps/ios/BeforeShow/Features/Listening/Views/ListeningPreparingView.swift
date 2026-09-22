import SwiftUI

struct ListeningPreparingView: View {
    let show: Show

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: BSSpacing.md) {
                ListeningRoomHeader(mode: .connecting)
                VStack(spacing: BSSpacing.roomy) {
                    ListeningDiscStage(disc: nil, diameter: proxy.size.width * ListeningStageTokens.discWidthFraction)
                    ProgressView().tint(ListeningStageTokens.status)
                    Text(BSLocalization.text("正在准备唱片"))
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .frame(maxWidth: .infinity)
                .background(alignment: .top) { ListeningStageSurface(width: proxy.size.width) }
                Spacer(minLength: 0)
            }
        }
        .coordinateSpace(name: "listeningContent")
        .background(BSColor.Stage.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
    }
}
