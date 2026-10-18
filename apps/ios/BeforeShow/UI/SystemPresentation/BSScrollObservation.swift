import SwiftUI
import UIKit

/// Exact timeline positioning on iOS 17, where ScrollPosition is unavailable.
@MainActor
final class BSScrollController {
    weak var scrollView: UIScrollView?
    private var pendingY: CGFloat?
    private var animated = false

    func scrollTo(y: CGFloat, animated: Bool = false) {
        pendingY = y
        self.animated = animated
        applyPosition()
    }

    func applyPosition() {
        guard let scrollView, let y = pendingY, scrollView.contentSize.height > 0 else { return }
        pendingY = nil
        let inset = scrollView.adjustedContentInset
        let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom + inset.top)
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: min(maximum, max(0, y)) - inset.top),
            animated: animated
        )
    }
}

struct BSScrollObservation: UIViewRepresentable {
    var enclosing = false
    var controller: BSScrollController? = nil
    let onOffset: (CGPoint) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.enclosing = enclosing
        view.controller = controller
        view.onOffset = onOffset
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.enclosing = enclosing
        view.controller = controller
        view.onOffset = onOffset
        view.connect()
    }

    final class ObserverView: UIView {
        var enclosing = false
        var controller: BSScrollController?
        var onOffset: ((CGPoint) -> Void)?
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            connect()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            connect()
            controller?.applyPosition()
        }

        func connect() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView ?? (enclosing ? nil : Self.findScroll(in: view, excluding: self)) {
                    guard scrollView !== scroll else { return }
                    scrollView = scroll
                    controller?.scrollView = scroll
                    observation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scroll, _ in
                        Task { @MainActor [weak self, weak scroll] in
                            guard let scroll else { return }
                            self?.onOffset?(CGPoint(
                                x: scroll.contentOffset.x + scroll.adjustedContentInset.left,
                                y: scroll.contentOffset.y + scroll.adjustedContentInset.top
                            ))
                        }
                    }
                    DispatchQueue.main.async { [weak self] in self?.controller?.applyPosition() }
                    return
                }
                ancestor = view.superview
            }
        }

        private static func findScroll(in view: UIView, excluding excluded: UIView) -> UIScrollView? {
            for child in view.subviews where child !== excluded {
                if let scroll = child as? UIScrollView { return scroll }
                if let scroll = findScroll(in: child, excluding: excluded) { return scroll }
            }
            return nil
        }
    }
}

extension View {
    func bsOnScrollOffset(enclosing: Bool = false, _ action: @escaping (CGPoint) -> Void) -> some View {
        background(BSScrollObservation(enclosing: enclosing, onOffset: action).allowsHitTesting(false))
    }
}
