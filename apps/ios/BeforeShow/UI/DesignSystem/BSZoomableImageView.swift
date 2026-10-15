import SwiftUI
import UIKit

/// Native UIScrollView wrapper for smooth pinch-to-zoom and double-tap zoom.
/// Aspect-fit at rest; single tap is reported after a double tap fails.
struct BSZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FittingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tag = 999
        scrollView.addSubview(imageView)

        // Double tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap gesture
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        scrollView.addGestureRecognizer(longPress)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onLongPress = onLongPress
        guard let imageView = scrollView.viewWithTag(999) as? UIImageView else { return }
        imageView.image = image
        scrollView.setNeedsLayout()
    }

    /// Keeps the whole image fitted to the screen whenever it is not zoomed in,
    /// including the first layout when SwiftUI hands over a zero-sized frame.
    final class FittingScrollView: UIScrollView {
        override func layoutSubviews() {
            super.layoutSubviews()
            guard zoomScale == minimumZoomScale, let imageView = viewWithTag(999) else { return }
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap, onLongPress: onLongPress)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSingleTap: (() -> Void)?
        var onLongPress: (() -> Void)?

        init(onSingleTap: (() -> Void)?, onLongPress: (() -> Void)?) {
            self.onSingleTap = onSingleTap
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.viewWithTag(999)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let view = scrollView.viewWithTag(999) else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            view.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let onLongPress else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: scrollView)
                let targetScale = min(3.0, scrollView.maximumZoomScale)
                let width = scrollView.bounds.width / targetScale
                let height = scrollView.bounds.height / targetScale
                let rect = CGRect(
                    x: location.x - (width / 2.0),
                    y: location.y - (height / 2.0),
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
