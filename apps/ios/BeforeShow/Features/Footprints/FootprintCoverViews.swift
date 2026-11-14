import ImageIO
import SwiftUI
import UIKit

struct FootprintCoverView: View {
    let show: Show
    let cover: FootprintCover?
    var showsMetadata = true

    var body: some View {
        Color.clear
            .overlay { coverContent }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.10)))
    }

    @ViewBuilder
    private var coverContent: some View {
        FootprintResolvedCoverImage(show: show, cover: cover)
    }
}

struct FootprintResolvedCoverImage: View {
    let show: Show
    let cover: FootprintCover?

    private var resolvedCover: FootprintCover {
        cover ?? FootprintCover(
            showID: show.id,
            source: .archive,
            badge: .archive,
            ordinal: 1,
            variant: FootprintArchiveCoverLayout.variant(for: show.id)
        )
    }

    var body: some View {
        switch resolvedCover.source {
        case let .local(url):
            FootprintCoverLocalImage(url: url) {
                FootprintTypographyCover(show: show, cover: resolvedCover)
            }
            .id(url)
        case let .remote(url):
            FootprintCoverRemoteImage(url: url) {
                FootprintTypographyCover(show: show, cover: resolvedCover)
            }
            .id(url)
        case .archive:
            FootprintTypographyCover(show: show, cover: resolvedCover)
        }
    }
}

private struct FootprintCoverLocalImage<Fallback: View>: View {
    let url: URL
    @ViewBuilder let fallback: Fallback
    @State private var image: UIImage?

    init(url: URL, @ViewBuilder fallback: () -> Fallback) {
        self.url = url
        self.fallback = fallback()
        _image = State(initialValue: FootprintLocalCoverCache.cached(url))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // `.local` 封面全部来自用户现场素材（记忆照片 / 票根 /
        // 本地封面文件），一律遮罩；远程 CDN 封面走 remote 分支，不遮。
        .bsMaskUserContent()
        .task(id: url) {
            guard image == nil else { return }
            image = await FootprintLocalCoverCache.image(at: url)
        }
    }
}

/// User photos decoded once, at screen size and off the main thread, so covers coming back into view show at once.
enum FootprintLocalCoverCache {
    nonisolated(unsafe) private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    static func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    static func image(at url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        let image = await Task.detached(priority: .userInitiated) { decode(url) }.value
        if let image, let cgImage = image.cgImage {
            cache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }

    /// A full-width cover on a 3× screen needs about 1300 pixels; photos are often 4000.
    nonisolated private static func decode(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

private struct FootprintCoverRemoteImage<Fallback: View>: View {
    let url: URL
    @ViewBuilder let fallback: Fallback
    @State private var image: UIImage?

    init(url: URL, @ViewBuilder fallback: () -> Fallback) {
        self.url = url
        self.fallback = fallback()
        _image = State(initialValue: ShowCoverImageCache.shared.memoryImage(for: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            guard image == nil else { return }
            image = await ShowCoverImageCache.shared.image(from: url)
        }
    }
}

struct FootprintTypographyCover: View {
    let show: Show
    let cover: FootprintCover

    var body: some View {
        let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city)?.uppercased() ?? "LIVE"
        let date = footprintEnhancementFullDateText(show.effectiveDate, calendar: show.timingCalendar())
        GeometryReader { proxy in
            let compact = proxy.size.width < 74
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: palette,
                    startPoint: cover.variant.isMultiple(of: 2) ? .topLeading : .bottomTrailing,
                    endPoint: cover.variant.isMultiple(of: 2) ? .bottomTrailing : .topLeading
                )
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: proxy.size.width * 1.1, height: proxy.size.width * 1.1)
                    .blur(radius: compact ? 12 : 20)
                    .offset(x: CGFloat(cover.variant % 3) * proxy.size.width * 0.12, y: cover.variant.isMultiple(of: 2) ? -proxy.size.height * 0.18 : proxy.size.height * 0.22)
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 1)
                    .padding(.top, proxy.size.height * (cover.variant == 1 ? 0.38 : 0.55))
                VStack(alignment: .leading, spacing: 0) {
                    Text("BEFORESHOW")
                        .font(.system(size: compact ? 5.5 : 8, weight: .bold))
                        .tracking(compact ? 0.7 : 1.2)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 2)
                    Text(city)
                        .font(.system(size: compact ? 8 : 13, weight: .semibold))
                        .tracking(compact ? 0.5 : 1.1)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(String(format: "%03d", cover.ordinal))
                        .font(.system(size: compact ? 22 : 34, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !compact {
                        Text(date)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
                .padding(compact ? 7 : 11)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var palette: [Color] {
        switch cover.variant {
        case 0: return [BSColor.Stage.surfaceRaised, BSColor.Stage.glowBlue.opacity(0.82)]
        case 1: return [BSColor.Stage.prepare.opacity(0.92), BSColor.Stage.surface]
        case 2: return [BSColor.Stage.accent.opacity(0.72), BSColor.Stage.surfaceRaised]
        default: return [Color(red: 0.18, green: 0.22, blue: 0.34), Color(red: 0.44, green: 0.28, blue: 0.46)]
        }
    }
}
