import SwiftUI

struct ListeningTransportButtonFace: View {
    let symbol: String
    let primary: Bool
    let active: Bool

    var body: some View {
        ZStack {
            Image(decorative: primary ? "button_primary_base" : "button_secondary_base")
                .resizable().scaledToFit()
                .scaleEffect(primary ? ListeningStageTokens.primaryAssetScale : ListeningStageTokens.secondaryAssetScale)
            Image(systemName: symbol)
                .font(.system(size: primary ? ListeningStageTokens.primarySymbol : ListeningStageTokens.secondarySymbol,
                              weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
        }
        .frame(width: primary ? ListeningStageTokens.primaryButton : ListeningStageTokens.secondaryButton,
               height: primary ? ListeningStageTokens.primaryButton : ListeningStageTokens.secondaryButton)
        .shadow(color: ListeningStageTokens.status.opacity(active ? 0.15 : 0), radius: BSSpacing.sm)
        .contentShape(Circle())
    }
}
