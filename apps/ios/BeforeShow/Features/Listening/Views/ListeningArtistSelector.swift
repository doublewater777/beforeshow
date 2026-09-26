import SwiftUI

private struct ListeningArtistSelectorItem: View {
    let artist: ListeningBrowseArtist
    let isSelected: Bool
    let onSelect: () -> Void
    let onConnect: () -> Void

    var body: some View {
        Button {
            if artist.isConnected {
                onSelect()
            } else {
                onConnect()
            }
        } label: {
            ListeningArtistChip(title: artist.name, isSelected: isSelected, isConnected: artist.isConnected) {
                ListeningArtistArtwork(url: artist.artworkURL, name: artist.name, size: BSListeningTokens.avatar)
                    .clipShape(Circle())
            }
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.94))
        .contextMenu {
            if artist.isConnected {
                Button {
                    onConnect()
                } label: {
                    Label(BSLocalization.text("重新匹配艺人"), systemImage: "arrow.triangle.2.circlepath")
                }
            } else {
                Button {
                    onConnect()
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

struct ListeningArtistSelector: View {
    let artists: [ListeningBrowseArtist]
    let selection: ListeningBrowseState.Scope
    let select: (ListeningBrowseState.Scope) -> Void
    let onConnect: (Int, String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: BSSpacing.sm) {
                allItem
                ForEach(artists) { artist in
                    ListeningArtistSelectorItem(
                        artist: artist,
                        isSelected: artist.isConnected && selection == .artist(artist.id),
                        onSelect: { select(.artist(artist.id)) },
                        onConnect: { onConnect(artist.slotIndex, artist.name) }
                    )
                }
            }
            .padding(.top, BSSpacing.sm)
        }
        .animation(BSListeningTokens.selectionAnimation, value: selection)
        .accessibilityIdentifier("listening.artistSelector")
    }

    private var allItem: some View {
        let isSelected = selection == .all
        return Button { select(.all) } label: {
            ListeningArtistChip(
                title: ListeningCopy.text("热门合辑"),
                isSelected: isSelected
            ) {
                Image(systemName: "opticaldisc")
                    .resizable()
                    .scaledToFit()
            }
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.94))
        .accessibilityLabel(ListeningCopy.text("热门合辑"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
