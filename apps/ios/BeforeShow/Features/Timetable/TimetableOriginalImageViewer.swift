import SwiftUI
import UIKit

/// Fullscreen zoomable image viewer for original timetable posters.
/// 100% aspect-fit, zero cropping, smooth pinch-to-zoom and pan.
struct TimetableOriginalImageViewer: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !images.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(0..<images.count, id: \.self) { index in
                        TimetableZoomableScrollView(image: images[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            }

            // Top chrome bar
            VStack {
                HStack {
                    if images.count > 1 {
                        Text("\(currentIndex + 1) / \(images.count)")
                            .font(TimetableStyle.mono(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(BSLocalization.text("关闭"))
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                Spacer()
            }
        }
    }
}

/// Native UIScrollView wrapper for smooth pinch-to-zoom and double-tap zoom.
struct TimetableZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
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

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = scrollView.viewWithTag(999) as? UIImageView else { return }
        imageView.image = image
        // Match bounds to scroll view frame
        if scrollView.bounds.size != .zero {
            imageView.frame = scrollView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
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

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: scrollView)
                let rect = CGRect(
                    x: location.x - 50,
                    y: location.y - 50,
                    width: 100,
                    height: 100
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
