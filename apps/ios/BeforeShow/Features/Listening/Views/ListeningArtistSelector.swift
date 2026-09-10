import SwiftUI

struct ListeningArtistSelector: View {
    let artists: [ListeningBrowseArtist]
    let selection: ListeningBrowseState.Scope
    let select: (ListeningBrowseState.Scope) -> Void
    let onConnect: (Int, String) -> Void
    @ScaledMetric(relativeTo: .caption) private var itemWidth = BSListeningTokens.artistWidth

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: BSSpacing.compact) {
                allItem
                ForEach(artists) { artist in
                    artistItem(artist)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, BSSpacing.xs)
        }
        .accessibilityIdentifier("listening.artistSelector")
    }

    private var allItem: some View {
        let isSelected = selection == .all
        return Button { select(.all) } label: {
            VStack(spacing: 6) {
                ZStack {
                    BSColor.Stage.surfaceRaised
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.Stage.muted)
                }
                .frame(width: BSListeningTokens.avatar, height: BSListeningTokens.avatar)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? BSColor.Stage.accent : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(color: isSelected ? BSColor.Stage.accent.opacity(0.35) : .clear, radius: 6)

                Text(ListeningCopy.text("热门合辑"))
                    .font(BSListeningTokens.captionMedium)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? BSColor.Stage.foreground : BSColor.Stage.muted)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: itemWidth, alignment: .top)
            .frame(minHeight: BSLayout.minTouchTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.94))
        .accessibilityLabel(ListeningCopy.text("热门合辑"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func artistItem(_ artist: ListeningBrowseArtist) -> some View {
        let isSelected = artist.isConnected && selection == .artist(artist.id)
        return Button {
            if artist.isConnected {
                select(.artist(artist.id))
            } else {
                onConnect(artist.slotIndex, artist.name)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if artist.isConnected {
                        ListeningArtistArtwork(url: artist.artworkURL, name: artist.name)
                            .frame(width: BSListeningTokens.avatar, height: BSListeningTokens.avatar)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            BSColor.Stage.surfaceRaised
                            Text(String(artist.name.prefix(1)))
                                .font(BSFont.headline)
                                .foregroundStyle(BSColor.Stage.dim)
                        }
                        .frame(width: BSListeningTokens.avatar, height: BSListeningTokens.avatar)
                        .clipShape(Circle())
                    }
                }
                .overlay {
                    if artist.isConnected {
                        Circle()
                            .strokeBorder(
                                isSelected ? BSColor.Stage.accent : Color.white.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !artist.isConnected {
                        ZStack {
                            Circle()
                                .fill(BSColor.Stage.surfaceRaised)
                            Circle()
                                .stroke(BSColor.Stage.border, lineWidth: 0.5)
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(BSColor.Stage.accent)
                        }
                        .frame(width: 15, height: 15)
                        .offset(x: 2, y: 2)
                    }
                }
                .shadow(color: isSelected ? BSColor.Stage.accent.opacity(0.35) : .clear, radius: 6)

                Text(artist.name)
                    .font(BSListeningTokens.captionMedium)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? BSColor.Stage.foreground : (artist.isConnected ? BSColor.Stage.muted : BSColor.Stage.dim))
                    .frame(maxWidth: .infinity)
            }
            .frame(width: itemWidth, alignment: .top)
            .frame(minHeight: BSLayout.minTouchTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.94))
        .contextMenu {
            if artist.isConnected {
                Button {
                    onConnect(artist.slotIndex, artist.name)
                } label: {
                    Label(BSLocalization.text("重新匹配艺人"), systemImage: "arrow.triangle.2.circlepath")
                }
            } else {
                Button {
                    onConnect(artist.slotIndex, artist.name)
                } label: {
                    Label(BSLocalization.text("连接 Apple Music"), systemImage: "link.badge.plus")
                }
            }
        }
        .accessibilityLabel(artist.isConnected ? artist.name : "\(artist.name), \(BSLocalization.text("未连接 Apple Music"))")
        .accessibilityHint(artist.isConnected ? "" : BSLocalization.text("轻点连接"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
