import Foundation
import SwiftUI
import UIKit

struct FootprintMemoryTile: View {
    let fragment: MemoryFragment

    private var firstMedia: MemoryMediaItem? { fragment.orderedMediaItems.first }

    var body: some View {
        Group {
            if let media = firstMedia {
                // 以瓦片尺寸为布局基准，避免竖图 fill 后撑高把右上角时长标签推出可视区。
                Color.clear
                    .overlay {
                        MemoryThumbnail(relativePath: media.thumbnailRelativePath ?? media.relativePath)
                    }
                    .overlay {
                        if media.kind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(FootprintDetailTokens.memoryPlayFont)
                                .foregroundColor(.white)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if media.kind == .video {
                            Text(durationText(media.videoDuration))
                                .font(FootprintDetailTokens.memoryBadgeFont)
                                .foregroundColor(FootprintDetailTokens.memoryDurationColor)
                                .padding(.horizontal, BSSpacing.sm)
                                .padding(.vertical, BSSpacing.xs)
                                .background(Color.black.opacity(0.34), in: Capsule())
                                .padding(BSSpacing.sm)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        FootprintTileCaption(
                            title: media.kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片"),
                            trailing: timeText(fragment.createdAt)
                        )
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(BSSpacing.compact)
                .overlay(alignment: .bottom) {
                    FootprintTileCaption(title: BSLocalization.text("文字"), trailing: timeText(fragment.createdAt), showsScrim: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: FootprintDetailTokens.memoryTileHeight)
        .clipped()
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

/// 贴底的纯文字说明：不占瓦片空间，只垫一层很淡的渐变保证可读。
struct FootprintTileCaption: View {
    let title: String
    var trailing: String? = nil
    var showsScrim = true

    var body: some View {
        HStack(alignment: .bottom, spacing: BSSpacing.sm) {
            Text(title)
            Spacer(minLength: 0)
            if let trailing { Text(trailing) }
        }
        .font(FootprintDetailTokens.memoryBadgeFont)
        .foregroundColor(FootprintDetailTokens.captionColor)
        .shadow(color: .black.opacity(showsScrim ? 0.45 : 0), radius: 3, y: 1)
        .padding(.horizontal, BSSpacing.compact)
        .padding(.top, BSSpacing.lg)
        .padding(.bottom, BSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            if showsScrim {
                LinearGradient(colors: [.clear, FootprintDetailTokens.captionScrim], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

struct FootprintKeepsakeTile: View {
    let kind: ShowAssetKind
    let asset: ShowAsset?

    var body: some View {
        Group {
            if let asset,
               let location = try? ShowAssetMediaLocation.applicationSupport() {
                Color.clear
                    .overlay {
                        FootprintLocalImage(
                            url: location.rootDirectory.appendingPathComponent(asset.relativePath),
                            contentMode: .fill
                        )
                    }
                    .overlay(alignment: .bottom) {
                        FootprintTileCaption(title: kind.title)
                    }
            } else {
                VStack(spacing: 0) {
                    ZStack {
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
                    .frame(maxWidth: .infinity)
                    .frame(height: FootprintDetailTokens.keepsakeMediaHeight)

                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(kind.title)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.foreground)
                        Text(BSLocalization.text("点击添加"))
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BSSpacing.compact)
                    .padding(.vertical, BSSpacing.xs)
                    .frame(height: FootprintDetailTokens.keepsakeInfoHeight, alignment: .leading)
                    .background(BSColor.Stage.surfaceRaised)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: FootprintDetailTokens.keepsakeTileHeight)
        .clipped()
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
