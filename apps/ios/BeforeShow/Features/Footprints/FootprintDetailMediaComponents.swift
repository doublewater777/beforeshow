import Foundation
import SwiftUI
import UIKit

struct FootprintMemoryTile: View {
    let fragment: MemoryFragment

    private var firstMedia: MemoryMediaItem? { fragment.orderedMediaItems.first }

    var body: some View {
        Group {
            if let media = firstMedia {
                VStack(spacing: 0) {
                    ZStack {
                        MemoryThumbnail(relativePath: media.thumbnailRelativePath ?? media.relativePath)
                        LinearGradient(
                            colors: [.clear, FootprintDetailTokens.memoryScrim],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        if media.kind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(FootprintDetailTokens.memoryPlayFont)
                                .foregroundColor(.white)
                            Text(durationText(media.videoDuration))
                                .font(FootprintDetailTokens.memoryBadgeFont)
                                .foregroundColor(FootprintDetailTokens.memoryDurationColor)
                                .padding(.horizontal, BSSpacing.sm)
                                .padding(.vertical, BSSpacing.xs)
                                .background(Color.black.opacity(0.34), in: Capsule())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(BSSpacing.sm)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: FootprintDetailTokens.memoryMediaHeight)
                    .clipped()

                    HStack(alignment: .bottom, spacing: BSSpacing.sm) {
                        Text(media.kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片"))
                        Spacer(minLength: 0)
                        Text(timeText(fragment.createdAt))
                    }
                    .font(FootprintDetailTokens.memoryBadgeFont)
                    .foregroundColor(FootprintDetailTokens.memoryMetadataColor)
                    .padding(.horizontal, BSSpacing.compact)
                    .frame(maxWidth: .infinity)
                    .frame(height: FootprintDetailTokens.memoryInfoHeight, alignment: .center)
                    .background(Color.black.opacity(0.18))
                }
            } else {
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    Image(systemName: "quote.opening")
                        .font(BSFont.headline.weight(.light))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(fragment.text ?? "")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        Text(BSLocalization.text("文字"))
                        Spacer(minLength: 0)
                        Text(timeText(fragment.createdAt))
                    }
                    .font(FootprintDetailTokens.memoryBadgeFont)
                    .foregroundColor(FootprintDetailTokens.memoryMetadataColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(BSSpacing.compact)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: FootprintDetailTokens.memoryTileHeight)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        let total = max(0, Int(duration ?? 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

struct FootprintKeepsakeTile: View {
    let kind: ShowAssetKind
    let asset: ShowAsset?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let asset,
                   let location = try? ShowAssetMediaLocation.applicationSupport() {
                    FootprintLocalImage(
                        url: location.rootDirectory.appendingPathComponent(asset.relativePath),
                        contentMode: .fill
                    )
                    LinearGradient(
                        colors: [.clear, FootprintDetailTokens.keepsakeScrim],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: kind.iconName)
                        .font(BSFont.title.weight(.light))
                        .foregroundColor(BSColor.Stage.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: FootprintDetailTokens.keepsakeMediaHeight)

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(kind.title)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
                if asset == nil {
                    Text(BSLocalization.text("点击添加"))
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BSSpacing.compact)
            .padding(.vertical, BSSpacing.xs)
            .frame(height: FootprintDetailTokens.keepsakeInfoHeight, alignment: .leading)
            .background(BSColor.Stage.surfaceRaised)
        }
        .frame(maxWidth: .infinity)
        .frame(height: FootprintDetailTokens.keepsakeTileHeight)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }
}

private struct FootprintLocalImage: View {
    let url: URL
    let contentMode: ContentMode
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                BSColor.Stage.surface
                    .overlay(Image(systemName: "photo").foregroundColor(BSColor.Stage.dim))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}
