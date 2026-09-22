import SwiftUI

struct ListeningTransportButtonFace: View {
    let symbol: String
    let primary: Bool
    let active: Bool
    @Environment(\.listeningSurfaceLight) private var surfaceLight

    var body: some View {
        ZStack {
            Image(decorative: primary ? "button_primary_base" : "button_secondary_base")
                .resizable().scaledToFit()
                .scaleEffect(primary ? ListeningStageTokens.primaryAssetScale : ListeningStageTokens.secondaryAssetScale)
                .brightness(primary ? ListeningStageTokens.primaryBrightness : ListeningStageTokens.secondaryBrightness)
                .contrast(primary ? ListeningStageTokens.primaryContrast : ListeningStageTokens.secondaryContrast)
            Circle()
                .fill(LinearGradient(colors: [surfaceLight.opacity(active ? 0.30 : 0.26), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .blendMode(.softLight)
            Image(systemName: symbol)
                .font(.system(size: primary ? ListeningStageTokens.primarySymbol : ListeningStageTokens.secondarySymbol,
                              weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
        }
        .frame(width: primary ? ListeningStageTokens.primaryButton : ListeningStageTokens.secondaryButton,
               height: primary ? ListeningStageTokens.primaryButton : ListeningStageTokens.secondaryButton)
        .background {
            Circle()
                .fill(.black.opacity(0.8))
                .padding(-ListeningStageTokens.discRim)
                .overlay(Circle().strokeBorder(surfaceLight.opacity(0.18), lineWidth: ListeningStageTokens.discRim))
        }
        .contentShape(Circle())
    }
}
