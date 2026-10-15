import CoreImage
import SwiftUI
import UIKit

/// Full-bleed artwork wash behind the disc detail: the cover blurred once off the main
/// thread into a static image, deepened toward the bottom so text stays legible.
struct ListeningDiscBackdrop: View {
    let artworkURL: URL?
    let tint: Color

    @State private var image: UIImage?

    init(artworkURL: URL?, tint: Color) {
        self.artworkURL = artworkURL
        self.tint = tint
        _image = State(initialValue: ListeningArtworkBlur.cached(artworkURL))
    }

    var body: some View {
        ZStack {
            BSColor.Stage.background

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
            } else {
                ListeningSheetBackground(tint: tint, intensity: BSListeningTokens.detailGlowOpacity)
            }

            LinearGradient(
                stops: [
                    .init(color: BSColor.Stage.background.opacity(0.1), location: 0),
                    .init(color: BSColor.Stage.background.opacity(0.4), location: 0.4),
                    .init(color: BSColor.Stage.background.opacity(0.85), location: 0.72),
                    .init(color: BSColor.Stage.background, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: image != nil)
        .task(id: artworkURL) {
            guard image == nil, let artworkURL else { return }
            image = await ListeningArtworkBlur.image(for: artworkURL)
        }
    }
}

@MainActor enum ListeningArtworkBlur {
    private static var cache: [URL: UIImage] = [:]

    static func cached(_ url: URL?) -> UIImage? {
        url.flatMap { cache[$0] }
    }

    static func image(for url: URL) async -> UIImage? {
        if let hit = cache[url] { return hit }
        guard let artwork = await ShowCoverImageCache.shared.image(from: url) else { return nil }
        let blurred = await Task.detached(priority: .userInitiated) { blur(artwork) }.value
        if let blurred { cache[url] = blurred }
        return blurred
    }

    /// A tiny copy is enough: blurred and scaled up it reads as soft colour fields.
    private nonisolated static func blur(_ artwork: UIImage) -> UIImage? {
        let side: CGFloat = 64
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            artwork.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let input = CIImage(image: small) else { return nil }
        let output = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 5)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.8])
            .cropped(to: input.extent)
        guard let cgImage = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
