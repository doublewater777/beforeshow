import CoreGraphics
import Observation

/// Keeps continuous header motion separate from the buffered card render window.
@MainActor
@Observable
final class TimetableMatrixViewport {
    private(set) var scrollOffsetX: CGFloat = 0
    @ObservationIgnored private(set) var scrollOffsetY: CGFloat = 0
    private(set) var visibleRect: CGRect = .zero
    /// Vertical scroll depth for the header lighting, 0...1 in coarse steps so
    /// headers redraw a handful of times instead of on every scroll frame.
    private(set) var headerProgress: CGFloat = 0

    @ObservationIgnored private var size: CGSize = .zero

    static let headerProgressDistance: CGFloat = 260
    private static let headerProgressSteps: CGFloat = 20

    func updateVerticalOffset(_ offset: CGFloat) {
        let clamped = max(0, offset)
        if scrollOffsetY != clamped {
            scrollOffsetY = clamped
            updateVisibleRect()
            let progress = (min(1, clamped / Self.headerProgressDistance) * Self.headerProgressSteps).rounded() / Self.headerProgressSteps
            if progress != headerProgress { headerProgress = progress }
        }
    }

    func updateHorizontalOffset(_ offset: CGFloat) {
        let clamped = max(0, offset)
        if scrollOffsetX != clamped {
            scrollOffsetX = clamped
            updateVisibleRect()
        }
    }

    func updateSize(_ size: CGSize) {
        self.size = size
        updateVisibleRect()
    }

    private func updateVisibleRect() {
        let buffer = TimetableStyle.matrixRenderBuffer
        let rect = CGRect(
            x: (scrollOffsetX / buffer).rounded(.down) * buffer - buffer,
            y: (scrollOffsetY / buffer).rounded(.down) * buffer - buffer,
            width: size.width + buffer * 3,
            height: size.height + buffer * 3
        )
        // Small scroll movements animate only the header, not every card.
        if rect != visibleRect { visibleRect = rect }
    }
}
