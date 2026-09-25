import SwiftUI

struct ListeningSheetBackground: View {
    var tint = BSColor.Stage.accent

    var body: some View {
        BSColor.Stage.background
            .overlay(alignment: .top) {
                RadialGradient(colors: [tint.opacity(BSListeningTokens.sheetGlowOpacity), .clear],
                               center: .top, startRadius: 0,
                               endRadius: BSListeningTokens.sheetGlowHeight)
                    .frame(height: BSListeningTokens.sheetGlowHeight)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
