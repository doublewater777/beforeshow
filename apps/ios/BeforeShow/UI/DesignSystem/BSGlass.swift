import SwiftUI

extension View {
    /// Apple's glass on iOS 26 and later; frosted material before that.
    func bsGlassCard(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(BSGlassCard(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

private struct BSGlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}
