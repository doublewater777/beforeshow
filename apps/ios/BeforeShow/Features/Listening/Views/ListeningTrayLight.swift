import SwiftUI

/// A lit landing edge makes the open tray a clear destination for the disc.
struct ListeningTrayLight: View {
    let phase: ListeningAtmospherePhase

    var body: some View {
        ZStack {
            Circle()
                .stroke(phase.color, lineWidth: BSListeningTokens.trayGlowWidth)
                .blur(radius: BSListeningTokens.trayGlowBlur)
                .opacity(phase == .placing ? 0.45 : 0.12)
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [phase.color, .clear, phase.color.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: BSListeningTokens.trayRingWidth
                )
                .opacity(phase == .placing ? 0.8 : 0.25)
        }
        .animation(BSListeningTokens.selectionAnimation, value: phase)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
