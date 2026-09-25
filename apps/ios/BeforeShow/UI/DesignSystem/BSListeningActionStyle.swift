import SwiftUI

/// Full-width actions share the same hierarchy across listening sheets and states.
struct BSListeningActionStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BSListeningTokens.headline)
            .frame(maxWidth: .infinity, minHeight: BSListeningTokens.actionHeight)
            .foregroundStyle(!isEnabled ? BSColor.Stage.muted : prominent ? BSListeningTokens.ink : BSColor.Stage.foreground)
            .background(prominent && isEnabled ? BSColor.Stage.accent : BSColor.Stage.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .strokeBorder(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
            }
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(BSListeningTokens.selectionAnimation, value: configuration.isPressed)
    }
}
