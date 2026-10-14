import CoreGraphics
import Observation

/// Keeps continuous header motion separate from the buffered card render window.
@MainActor
@Observable
final class TimetableMatrixViewport {
    private(set) var scrollOffsetX: CGFloat = 0
    private(set) var scrollOffsetY: CGFloat = 0
    private(set) var visibleRect: CGRect = .zero

    @ObservationIgnored private var size: CGSize = .zero

    func updateVerticalOffset(_ offset: CGFloat) {
        let clamped = max(0, offset)
        if scrollOffsetY != clamped {
            scrollOffsetY = clamped
            updateVisibleRect()
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
