import SafariServices
import UIKit
import SwiftUI

struct ArtistAvatarThumb: View {
    let url: URL?
    var size: CGFloat = 28

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
        } else {
            placeholder
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundColor(.white.opacity(0.46))
            )
    }
}

/// 阵容横滑条:现场详情 / 足迹详情共用。头像在上艺名在下,点击跳 Apple Music
/// (识别过的直达艺人页,未识别的按艺名搜索);未识别头像用首字符占位圆。

struct ArtistLineupStrip: View {
    let artists: [ArtistSlot]

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.md) {
                ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                    item(artist)
                }
            }
        }
    }

    private func item(_ artist: ArtistSlot) -> some View {
        Button {
            openInAppleMusic(artist)
        } label: {
            VStack(spacing: BSSpacing.xs) {
                avatar(artist)

                Text(artist.name)
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.format("在 Apple Music 中查看 %@", artist.name))
    }

    private func avatar(_ artist: ArtistSlot) -> some View {
        if let urlString = artist.avatarURL,
           let url = URL(string: urlString) {
            return AnyView(ArtistAvatarThumb(url: url, size: 48))
        }
        let initial = String(artist.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
        return AnyView(
            Text(initial.isEmpty ? "?" : initial)
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
        )
    }

    private func openInAppleMusic(_ artist: ArtistSlot) {
        if let urlString = artist.appleMusicURL,
           let url = URL(string: urlString) {
            openURL(url)
            return
        }
        var components = URLComponents(string: "https://music.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: artist.name)]
        if let url = components?.url {
            openURL(url)
        }
    }
}
