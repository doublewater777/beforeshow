import SwiftUI

struct ListeningEmptyArtwork: View {
    var body: some View {
        ZStack {
            Image(CDPlayerConfiguration.standard.assets.disc)
                .resizable()
                .frame(width: BSListeningTokens.emptyArtwork * BSListeningTokens.emptyDiscFraction,
                       height: BSListeningTokens.emptyArtwork * BSListeningTokens.emptyDiscFraction)
                .offset(x: BSListeningTokens.emptyArtwork * BSListeningTokens.emptyDiscOffset)
            RoundedRectangle(cornerRadius: BSRadius.sm)
                .fill(LinearGradient(colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: BSRadius.sm)
                        .strokeBorder(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
                }
                .overlay {
                    Image(systemName: "music.note")
                        .font(BSFont.heroTitle)
                        .foregroundStyle(BSColor.Stage.accent)
                }
                .rotationEffect(.degrees(BSListeningTokens.sleeveAngles[0]))
                .offset(x: -BSSpacing.md)
        }
        .frame(width: BSListeningTokens.emptyArtwork, height: BSListeningTokens.emptyArtwork)
        .padding(BSSpacing.xl)
        .background {
            Circle().fill(BSColor.Stage.accent.opacity(BSListeningTokens.sheetGlowOpacity))
                .blur(radius: BSListeningTokens.haloBlur)
        }
        .accessibilityHidden(true)
    }
}
