import SwiftUI

struct CDPlayerControlFace: View {
    let control: CDControl
    let isPlaying: Bool
    let isOpen: Bool
    private var primary: Bool { control == .playPause }
    private var glow: Color { isPlaying ? CDPlayerSurfaceTokens.lcdGlow : BSColor.Stage.accent.opacity(0.65) }

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.65))
            Circle().fill(LinearGradient(colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(BSListeningTokens.hairline)
            Circle().strokeBorder(primary ? glow : .white.opacity(control == .open ? 0.14 : 0.28), lineWidth: primary ? 1.5 : BSListeningTokens.hairline)
                .shadow(color: primary ? glow.opacity(0.25) : .clear, radius: BSSpacing.sm)
            Image(systemName: symbol)
                .font(.system(size: primary ? CDPlayerSurfaceTokens.primaryIcon : (control == .open ? CDPlayerSurfaceTokens.openIcon : CDPlayerSurfaceTokens.secondaryIcon), weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground.opacity(control == .open ? 0.65 : 0.95))
        }
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch control {
        case .previous: "backward.end.fill"
        case .playPause: isPlaying ? "pause.fill" : "play.fill"
        case .next: "forward.end.fill"
        case .open: isOpen ? "chevron.down" : "eject.fill"
        case .stop: "stop.fill"
        }
    }
}
