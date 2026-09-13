import SwiftUI

struct ListeningArtistSelector: View {
    let artists: [ListeningBrowseArtist]
    let selection: ListeningBrowseState.Scope
    let select: (ListeningBrowseState.Scope) -> Void
    let onConnect: (Int, String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.xs) {
                allItem
                ForEach(artists) { artist in
                    artistItem(artist)
                }
            }
            .padding(.vertical, BSSpacing.xs)
        }
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

    private func artistItem(_ artist: ListeningBrowseArtist) -> some View {
        let isSelected = artist.isConnected && selection == .artist(artist.id)
        return Button {
            if artist.isConnected {
                select(.artist(artist.id))
            } else {
                onConnect(artist.slotIndex, artist.name)
            }
        } label: {
            ListeningArtistChip(title: artist.name, isSelected: isSelected, isConnected: artist.isConnected) {
                ListeningArtistArtwork(url: artist.artworkURL, name: artist.name)
                    .clipShape(Circle())
            }
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
