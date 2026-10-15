import ImageIO
import Photos
import SwiftUI
import UIKit

/// Shared fullscreen shell for viewing images: black backdrop, optional paging with a
/// "1 / N" counter, and a bottom slot for actions. Pages decide their own gestures
/// (usually `BSZoomableImagePage`, whose single tap dismisses).
struct BSFullscreenImageViewer<Page: View, BottomBar: View>: View {
    let pageCount: Int
    @Binding var currentIndex: Int
    @ViewBuilder let page: (Int) -> Page
    @ViewBuilder let bottomBar: () -> BottomBar

    init(
        pageCount: Int,
        currentIndex: Binding<Int>,
        @ViewBuilder page: @escaping (Int) -> Page,
        @ViewBuilder bottomBar: @escaping () -> BottomBar = { EmptyView() }
    ) {
        self.pageCount = pageCount
        _currentIndex = currentIndex
        self.page = page
        self.bottomBar = bottomBar
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if pageCount > 1 {
                TabView(selection: $currentIndex) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        page(index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            } else if pageCount == 1 {
                page(0)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if pageCount > 1 {
                Text("\(currentIndex + 1) / \(pageCount)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            bottomBar()
        }
        .preferredColorScheme(.dark)
    }
}

/// Where a fullscreen page gets its image.
enum BSFullscreenImageSource: Equatable {
    /// Show covers: remote or local, served through `ShowCoverImageCache`.
    case cover(URL)
    /// Local originals (memory photos, tickets), downsampled so a large photo
    /// never decodes at full resolution.
    case file(URL)
    case image(UIImage)
}

/// One zoomable page: loads its source off the main thread, then hands it to
/// `BSZoomableImageView`. Long press offers saving the original to Photos unless the
/// caller takes over the long press.
struct BSZoomableImagePage: View {
    let source: BSFullscreenImageSource
    var onSingleTap: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var isOfferingSave = false
    @State private var isSaving = false
    @State private var toast: BSToastPayload?

    init(
        source: BSFullscreenImageSource,
        onSingleTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.source = source
        self.onSingleTap = onSingleTap
        self.onLongPress = onLongPress
        _image = State(initialValue: Self.immediateImage(for: source))
    }

    var body: some View {
        ZStack {
            if let image {
                BSZoomableImageView(
                    image: image,
                    onSingleTap: onSingleTap,
                    onLongPress: onLongPress ?? { isOfferingSave = true }
                )
            } else {
                Group {
                    if didFail {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onSingleTap?() }
            }
        }
        .confirmationDialog("", isPresented: $isOfferingSave, titleVisibility: .hidden) {
            Button(BSLocalization.text("保存图片")) {
                Task { await save() }
            }
            .disabled(isSaving)
        }
        .bsToastOverlay(toast, bottomPadding: 36)
        .task(id: source) {
            guard image == nil else { return }
            let loaded = await Self.load(source)
            guard !Task.isCancelled else { return }
            image = loaded
            didFail = loaded == nil
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BSPhotoLibrarySaver.save(source)
            toast = BSToastPayload(tone: .success, message: BSLocalization.text("已保存到相册"))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? BSLocalization.text("照片保存失败，请重试。")
            toast = BSToastPayload(tone: .failure, message: message)
        }
        let shown = toast
        try? await Task.sleep(for: .milliseconds(2200))
        if toast == shown { toast = nil }
    }

    private static func immediateImage(for source: BSFullscreenImageSource) -> UIImage? {
        switch source {
        case .cover(let url): ShowCoverImageCache.shared.memoryImage(for: url)
        case .file: nil
        case .image(let image): image
        }
    }

    private static func load(_ source: BSFullscreenImageSource) async -> UIImage? {
        switch source {
        case .cover(let url):
            return await ShowCoverImageCache.shared.image(from: url)
        case .file(let url):
            return await Task.detached(priority: .userInitiated) {
                downsampledImage(at: url)
            }.value
        case .image(let image):
            return image
        }
    }

    /// Long edge capped well above screen pixels so zooming stays sharp.
    private nonisolated static let maxPixelSize = 3_000

    private nonisolated static func downsampledImage(at url: URL) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Saves what a fullscreen page shows, at full quality, to Photos.
enum BSPhotoLibrarySaver {
    static func save(_ source: BSFullscreenImageSource) async throws {
        switch source {
        case .image(let image):
            try await FootprintPhotoLibrary.save(image)
        case .file(let url):
            try await saveFile(url, as: .photo)
        case .cover(let url):
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                data = try await URLSession.shared.data(from: url).0
            }
            try await FootprintPhotoLibrary.save(reencoded(data))
        }
    }

    /// Hands the original file to Photos so HEIC, HDR and metadata survive; formats
    /// Photos rejects fall back to a re-encoded image.
    static func saveFile(_ url: URL, as type: PHAssetResourceType) async throws {
        do {
            try await FootprintPhotoLibrary.saveFile(url, as: type)
        } catch FootprintPhotoSaveError.saveFailed where type == .photo {
            try await FootprintPhotoLibrary.save(reencoded(Data(contentsOf: url)))
        }
    }

    /// 部分封面实为 WebP(大麦/阿里 CDN 常见),直接交给 Photos 会报
    /// PHPhotosErrorDomain 3302;先重编码成 JPEG 再保存。
    private static func reencoded(_ data: Data) throws -> UIImage {
        guard let decoded = UIImage(data: data),
              let jpegData = decoded.jpegData(compressionQuality: 0.95),
              let image = UIImage(data: jpegData) else {
            throw FootprintPhotoSaveError.saveFailed
        }
        return image
    }
}
