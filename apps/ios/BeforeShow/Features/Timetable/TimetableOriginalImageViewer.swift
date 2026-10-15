import SwiftUI
import UIKit

struct TimetableOriginalImagePages: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    var onSingleTap: (() -> Void)? = nil

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(images.indices, id: \.self) { index in
                BSZoomableImageView(image: images[index], onSingleTap: onSingleTap)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

struct TimetableSavedImagesView: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    let isLoading: Bool
    let onRetry: () -> Void
    var onRecognizePoster: (() -> Void)? = nil
    var onAddPhotos: (() -> Void)? = nil
    @Binding var isChromeVisible: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if images.isEmpty {
                VStack(spacing: BSSpacing.md) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(BSFont.V3.title1)
                    Text(BSLocalization.text("未能读取已保存的原图"))
                        .font(BSFont.body)
                    Button(action: onRetry) {
                        Label(BSLocalization.text("重试"), systemImage: "arrow.clockwise")
                    }
                    .frame(minHeight: BSLayout.minTouchTarget)
                }
                .foregroundStyle(TimetableStyle.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimetableOriginalImagePages(
                    images: images,
                    currentIndex: $currentIndex,
                    onSingleTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isChromeVisible.toggle()
                        }
                    }
                )
                .ignoresSafeArea()

                if isChromeVisible {
                    bottomOverlay
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            if images.count > 1 {
                HStack(spacing: 6) {
                    ForEach(images.indices, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.35))
                            .frame(width: index == currentIndex ? 7 : 5, height: index == currentIndex ? 7 : 5)
                            .animation(.easeInOut(duration: 0.2), value: currentIndex)
                    }
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(TimetableStyle.mono(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }

            HStack(spacing: 10) {
                if let onRecognizePoster {
                    Button(action: onRecognizePoster) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                            Text(BSLocalization.text("智能识别此图"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(TimetableStyle.background)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Capsule().fill(TimetableStyle.foreground))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    }
                    .buttonStyle(TimetablePressStyle())
                }

                if currentIndex >= 0, currentIndex < images.count {
                    ShareLink(
                        item: Image(uiImage: images[currentIndex]),
                        preview: SharePreview(BSLocalization.text("演出时刻表"), image: Image(uiImage: images[currentIndex]))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TimetableStyle.foreground)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(TimetablePressStyle())
                    .accessibilityLabel(BSLocalization.text("分享"))
                }

                if let onAddPhotos {
                    Button(action: onAddPhotos) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TimetableStyle.foreground)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(TimetablePressStyle())
                    .accessibilityLabel(BSLocalization.text("更换图片"))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

/// Fullscreen zoomable image viewer for original timetable posters.
/// 100% aspect-fit, zero cropping, smooth pinch-to-zoom and pan.
/// Single tap anywhere on the screen exits fullscreen; double tap zooms.
struct TimetableOriginalImageViewer: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !images.isEmpty {
                TimetableOriginalImagePages(
                    images: images,
                    currentIndex: $currentIndex,
                    onSingleTap: onDismiss
                )
            }

            if images.count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(currentIndex + 1) / \(images.count)")
                            .font(TimetableStyle.mono(13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    .padding(.top, 18)

                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .preferredColorScheme(.dark)
    }
}
