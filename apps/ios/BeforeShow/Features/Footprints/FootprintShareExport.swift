import Foundation
import SwiftUI
import UIKit

// MARK: - Footprint Share Export

enum FootprintCoverExportWarmup {
    static func warm(covers: [UUID: FootprintCover]) async {
        await withTaskGroup(of: Void.self) { group in
            for cover in covers.values {
                guard case let .remote(url) = cover.source else { continue }
                group.addTask {
                    _ = await ShowCoverImageCache.shared.image(from: url)
                }
            }
        }
    }

    /// Warms artist artwork/avatar images so the export tree's synchronous
    /// disk-cache reads hit (its `.task`/AsyncImage loads never complete
    /// before the snapshot).
    static func warm(artists: [FootprintArtistArchiveItem]) async {
        await withTaskGroup(of: Void.self) { group in
            for item in artists {
                for url in [item.albumArtworkURL, item.artworkURL].compactMap({ $0 }) {
                    group.addTask {
                        _ = await ShowCoverImageCache.shared.image(from: url)
                    }
                }
            }
        }
    }
}

enum FootprintShareImageExport {
    @MainActor
    static func render<Content: View>(
        _ content: Content,
        size: CGSize,
        scale: CGFloat = 1
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: content.frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Renders content at a fixed width with its intrinsic (full) height —
    /// the "long screenshot" path for the whole dashboard. Height is measured
    /// via a hosting controller, then the image is rendered in vertical tiles
    /// and stitched: ImageRenderer renders fully black once the pixel height
    /// exceeds the ~8192px GPU texture cap, so each tile stays below it.
    /// Tiles are blitted 1:1 in pixel space so a scaled `UIImage.draw` cannot
    /// interpolate the whole image soft.
    /// 最终拼接 bitmap 是一次性全尺寸分配(RGBA 4 字节/px)。50M px ≈ 200MB,
    /// 超出预算直接放弃导出(调用方弹失败提示),避免超大档案长图把进程 jetsam。
    static let maximumStitchedPixels: CGFloat = 50_000_000

    static func fitsStitchedMemoryBudget(width: CGFloat, height: CGFloat, scale: CGFloat) -> Bool {
        let pixels = (width * scale).rounded() * (height * scale).rounded()
        return pixels > 0 && pixels <= maximumStitchedPixels
    }

    @MainActor
    static func renderLong<Content: View>(
        _ content: Content,
        width: CGFloat,
        scale: CGFloat = 1
    ) -> UIImage? {
        let controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        let fitted = controller.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        guard fitted.height.isFinite, fitted.height > 0, fitted.height < 100_000 else { return nil }
        let size = CGSize(width: width, height: ceil(fitted.height))
        let outputScale = max(scale, 1)
        guard fitsStitchedMemoryBudget(width: size.width, height: size.height, scale: outputScale) else { return nil }
        let pixelWidth = (size.width * outputScale).rounded()
        let pixelHeight = (size.height * outputScale).rounded()
        let tileHeight = min(size.height, floor(7000 / outputScale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let stitcher = UIGraphicsImageRenderer(
            size: CGSize(width: pixelWidth, height: pixelHeight),
            format: format
        )
        var didFail = false
        let stitched = stitcher.image { ctx in
            ctx.cgContext.interpolationQuality = .none
            var offsetY: CGFloat = 0
            while offsetY < size.height {
                let height = min(tileHeight, size.height - offsetY)
                let tile = content
                    .frame(width: width, height: size.height, alignment: .top)
                    .offset(y: -offsetY)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
                let renderer = ImageRenderer(content: tile)
                renderer.proposedSize = ProposedViewSize(width: width, height: height)
                renderer.scale = outputScale
                guard let tileImage = renderer.uiImage, let cgImage = tileImage.cgImage else {
                    didFail = true
                    break
                }
                let dest = CGRect(
                    x: 0,
                    y: (offsetY * outputScale).rounded(),
                    width: CGFloat(cgImage.width),
                    height: CGFloat(cgImage.height)
                )
                UIImage(cgImage: cgImage, scale: 1, orientation: .up).draw(in: dest)
                offsetY += height
            }
        }
        guard !didFail else { return nil }
        guard let cgImage = stitched.cgImage else { return stitched }
        return UIImage(cgImage: cgImage, scale: outputScale, orientation: .up)
    }

    @MainActor
    static func save<Content: View>(
        _ content: Content,
        size: CGSize,
        scale: CGFloat = 1
    ) async throws {
        guard let image = render(content, size: size, scale: scale) else {
            throw FootprintPhotoSaveError.rendererFailed
        }
        try await FootprintPhotoLibrary.save(image)
    }

    @MainActor
    static func saveLong<Content: View>(
        _ content: Content,
        width: CGFloat,
        scale: CGFloat = 1
    ) async throws {
        guard let image = renderLong(content, width: width, scale: scale) else {
            throw FootprintPhotoSaveError.rendererFailed
        }
        try await FootprintPhotoLibrary.save(image)
    }
}
