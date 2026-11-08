import SwiftUI

/// Closing the timetable by pulling down, without the grid's own scrolling ever closing it.
/// A drag that starts anywhere in the top bar takes the whole sheet with the finger (buttons there
/// still tap); past a clear distance or on a decisive flick it keeps going down and closes in the
/// same motion. Short pulls spring back. Drags that start on the grid only scroll the grid.
struct TimetablePullToClose: ViewModifier {
    let isEnabled: Bool
    let onClose: () -> Void

    @State private var pull: CGFloat = 0
    @State private var isTracking = false
    @State private var isPastThreshold = false
    @State private var isClosing = false

    private static let barHeight: CGFloat = 64
    private static let threshold: CGFloat = 120
    private static let flick: CGFloat = 300
    private static let space = "timetable.pull"

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .background(TimetableStyle.background)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(isPastThreshold ? 0.7 : 0.3))
                        .frame(width: 36, height: 5)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .offset(y: pull)
                .simultaneousGesture(drag(height: proxy.size.height), isEnabled: isEnabled && !isClosing)
        }
        .coordinateSpace(.named(Self.space))
        .presentationBackground(.clear)
        .sensoryFeedback(.impact(weight: .light), trigger: isPastThreshold) { _, past in past }
        .accessibilityAction(named: BSLocalization.text("关闭")) { if isEnabled { onClose() } }
    }

    private func drag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !isTracking {
                    // Only a downward drag that began in the top bar belongs to the sheet.
                    guard value.startLocation.y < Self.barHeight, value.translation.height > abs(value.translation.width) else { return }
                    isTracking = true
                }
                pull = max(0, value.translation.height)
                isPastThreshold = pull > Self.threshold
            }
            .onEnded { value in
                guard isTracking else { return }
                isTracking = false
                isPastThreshold = false
                if value.translation.height > Self.threshold || value.predictedEndTranslation.height > Self.flick {
                    isClosing = true
                    withAnimation(.easeIn(duration: 0.18)) { pull = height } completion: { onClose() }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { pull = 0 }
                }
            }
    }
}

extension View {
    func timetablePullToClose(isEnabled: Bool, onClose: @escaping () -> Void) -> some View {
        modifier(TimetablePullToClose(isEnabled: isEnabled, onClose: onClose))
    }
}
