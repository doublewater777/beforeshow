import SwiftUI
import SwiftData
import UIKit

struct ShowCoverFullscreenPreview: View {
    let urlString: String?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isSaving = false
    @State private var toast: BSToastPayload?

    init(urlString: String?) {
        self.urlString = urlString
        _image = State(initialValue: Self.coverURL(urlString).flatMap(ShowCoverImageCache.shared.memoryImage(for:)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                BSZoomableImageView(image: image, onSingleTap: { dismiss() })
                    .ignoresSafeArea()
            } else {
                ShowCoverImageView(
                    urlString: urlString,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fit,
                    enforcesAspectRatio: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, BSSpacing.roomy)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            }
        }
        .task {
            guard image == nil, let url = Self.coverURL(urlString) else { return }
            image = await ShowCoverImageCache.shared.image(from: url)
        }
        .overlay(alignment: .bottom) {
            if urlString != nil {
                Button {
                    Task { await saveCover() }
                } label: {
                    Label(BSLocalization.text("保存图片"), systemImage: "square.and.arrow.down")
                        .font(BSFont.V3.small.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, BSSpacing.md)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .padding(.bottom, BSSpacing.lg)
            }
        }
        .bsToastOverlay(toast, bottomPadding: 90)
        .preferredColorScheme(.dark)
    }

    private static func coverURL(_ urlString: String?) -> URL? {
        urlString.flatMap(URL.init(string:))
    }

    @MainActor
    private func saveCover() async {
        guard !isSaving, let urlString, let url = URL(string: urlString) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // 部分封面 URL 实为 WebP(大麦/阿里 CDN 常见),直接交给 Photos 会报
            // PHPhotosErrorDomain 3302;先重编码成 JPEG 再保存。
            guard let decoded = UIImage(data: data),
                  let jpegData = decoded.jpegData(compressionQuality: 0.95),
                  let image = UIImage(data: jpegData) else {
                throw FootprintPhotoSaveError.saveFailed
            }
            try await FootprintPhotoLibrary.save(image)
            presentToast(.success, message: BSLocalization.text("已保存到相册"))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? BSLocalization.text("照片保存失败，请重试。")
            presentToast(.failure, message: message)
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload { toast = nil }
        }
    }
}
