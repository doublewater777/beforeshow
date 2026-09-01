import SwiftUI
import UIKit

struct FootprintCoverView: View {
    let show: Show
    let cover: FootprintCover?
    var showsMetadata = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            coverContent
            LinearGradient(colors: [.clear, .black.opacity(0.66)], startPoint: .center, endPoint: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
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
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 2)
                    Text(city)
                        .font(.system(size: compact ? 8 : 13, weight: .semibold))
                        .tracking(compact ? 0.5 : 1.1)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(String(format: "%03d", cover.ordinal))
                        .font(.system(size: compact ? 22 : 34, weight: .ultraLight, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !compact {
                        Text(date)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.68))
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
