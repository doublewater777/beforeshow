import SwiftUI

/// Closing the timetable by pulling down, without the grid's own scrolling ever closing it:
/// only the grab strip at the very top answers, the page follows the finger, and it closes
/// only past a clear distance (or a decisive flick). Short pulls spring back.
struct TimetablePullToClose: ViewModifier {
    let isEnabled: Bool
    let onClose: () -> Void

    @State private var pull: CGFloat = 0
    @State private var isPastThreshold = false

    private static let threshold: CGFloat = 140
    private static let flick: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .offset(y: pull)
            .overlay(alignment: .top) {
                if isEnabled {
                    grabStrip
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isPastThreshold) { _, past in past }
    }

    private var grabStrip: some View {
        Capsule()
            .fill(Color.white.opacity(isPastThreshold ? 0.7 : 0.35))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        // Resist a little so the page feels attached, not loose.
                        pull = max(0, value.translation.height) * 0.85
                        isPastThreshold = value.translation.height > Self.threshold
                    }
                    .onEnded { value in
                        if value.translation.height > Self.threshold || value.predictedEndTranslation.height > Self.flick {
                            onClose()
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { pull = 0 }
                        }
                        isPastThreshold = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(BSLocalization.text("关闭"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onClose() }
    }
}

extension View {
    func timetablePullToClose(isEnabled: Bool, onClose: @escaping () -> Void) -> some View {
        modifier(TimetablePullToClose(isEnabled: isEnabled, onClose: onClose))
    }
}
