import SwiftUI
import UIKit

/// Floating original-image window for comparing against the parsed schedule.
/// Preserves exact aspect ratio (scaledToFit), zero cropping.
/// Drag to move, tap to open full-screen pinch-to-zoom viewer.
struct TimetableOriginalImagePiP: View {
    let images: [UIImage]
    @Binding var page: Int
    let onExpandFullScreen: () -> Void
    let onClose: () -> Void

    init(
        images: [UIImage],
        page: Binding<Int>? = nil,
        onExpandFullScreen: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        self.images = images
        self._page = page ?? .constant(0)
        self.onExpandFullScreen = onExpandFullScreen
        self.onClose = onClose
    }

    private enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    @State private var corner: Corner = .bottomTrailing
    @State private var drag: CGSize = .zero

    private static let margin: CGFloat = 14
    private static let topInset: CGFloat = 56
    private static let bottomInset: CGFloat = 76

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: 140, height: 190)
            let origin = position(for: corner, size: size, in: geo.size)

            window(size: size)
                .position(x: origin.x + size.width / 2 + drag.width, y: origin.y + size.height / 2 + drag.height)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            let center = CGPoint(
                                x: origin.x + size.width / 2 + value.translation.width,
                                y: origin.y + size.height / 2 + value.translation.height
                            )
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                corner = nearestCorner(to: center, in: geo.size)
                                drag = .zero
                            }
                        }
                )
                .onTapGesture {
                    onExpandFullScreen()
                }
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func window(size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.88)

            if !images.isEmpty {
                let img = images[min(page, images.count - 1)]
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: size.width, maxHeight: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(6)
            .accessibilityLabel(BSLocalization.text("关闭原图"))
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                if images.count > 1 {
                    Button {
                        page = (page + 1) % images.count
                    } label: {
                        Text("\(page + 1)/\(images.count)")
                            .font(TimetableStyle.mono(10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                Button(action: onExpandFullScreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(BSLocalization.text("全屏查看"))
            }
            .padding(6)
        }
        .shadow(color: .black.opacity(0.65), radius: 20, y: 18)
    }

    private func position(for corner: Corner, size: CGSize, in container: CGSize) -> CGPoint {
        let left = Self.margin
        let right = container.width - Self.margin - size.width
        let top = Self.topInset
        let bottom = container.height - Self.bottomInset - size.height
        switch corner {
        case .topLeading: return CGPoint(x: left, y: top)
        case .topTrailing: return CGPoint(x: right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: bottom)
        case .bottomTrailing: return CGPoint(x: right, y: bottom)
        }
    }

    private func nearestCorner(to point: CGPoint, in container: CGSize) -> Corner {
        let isTop = point.y < container.height / 2
        let isLeading = point.x < container.width / 2
        switch (isTop, isLeading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }
}
