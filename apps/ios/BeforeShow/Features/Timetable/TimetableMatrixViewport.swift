import CoreGraphics
import Observation

/// Keeps continuous header motion separate from the buffered card render window.
@MainActor
@Observable
final class TimetableMatrixViewport {
    private(set) var scrollOffsetY: CGFloat = 0
    private(set) var visibleRect: CGRect = .zero

    @ObservationIgnored private var scrollOffsetX: CGFloat = 0
    @ObservationIgnored private var size: CGSize = .zero

    func updateVerticalOffset(_ offset: CGFloat) {
        scrollOffsetY = max(0, offset)
        updateVisibleRect()
    }

    func updateHorizontalOffset(_ offset: CGFloat) {
        scrollOffsetX = max(0, offset)
        updateVisibleRect()
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
