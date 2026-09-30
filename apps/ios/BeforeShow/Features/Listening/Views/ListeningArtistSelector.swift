import SwiftUI

private struct ListeningArtistSelectorItem: View {
    let artist: ListeningBrowseArtist
    let isSelected: Bool
    let onSelect: (CGRect) -> Void
    let onConnect: () -> Void
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            onSelect(frame)
        } label: {
            ListeningArtistChip(title: artist.name, isSelected: isSelected, isConnected: artist.isConnected) {
                ListeningArtistArtwork(url: artist.artworkURL, name: artist.name, size: BSListeningTokens.avatar)
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("artistSelectorViewport")) } action: { frame = $0 }
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
        .accessibilityHint(artist.isConnected ? "" : BSLocalization.text("轻点查看"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ListeningArtistSelector: View {
    let artists: [ListeningBrowseArtist]
    let selection: ListeningBrowseState.Scope
    let select: (ListeningBrowseState.Scope) -> Void
    let onConnect: (Int, String) -> Void
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var allFrame: CGRect = .zero

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: BSSpacing.sm) {
                allItem {
                    select(.all)
                    revealIfNeeded(allFrame)
                }
                if !artists.isEmpty {
                    Rectangle()
                        .fill(BSColor.Stage.border)
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)
                        .accessibilityHidden(true)
                }
                ForEach(artists) { artist in
                    ListeningArtistSelectorItem(
                        artist: artist,
                        isSelected: selection == .artist(artist.id),
                        onSelect: { frame in
                            select(.artist(artist.id))
                            revealIfNeeded(frame)
                        },
                        onConnect: { onConnect(artist.slotIndex, artist.name) }
                    )
                }
            }
            .padding(.horizontal, BSSpacing.roomy)
        }
        .scrollPosition($scrollPosition)
        .frame(height: BSLayout.minTouchTarget)
        .padding(.top, BSSpacing.sm)
        .coordinateSpace(name: "artistSelectorViewport")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, offset in scrollOffset = offset }
        .accessibilityIdentifier("listening.artistSelector")
    }

    private func allItem(onSelect: @escaping () -> Void) -> some View {
        let isSelected = selection == .all
        return Button(action: onSelect) {
            ListeningArtistChip(
                title: ListeningCopy.text("热门合辑"),
                isSelected: isSelected
            ) {
                Image(systemName: "opticaldisc")
                    .resizable()
                    .scaledToFit()
            }
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("artistSelectorViewport")) } action: { allFrame = $0 }
        .accessibilityLabel(ListeningCopy.text("热门合辑"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func revealIfNeeded(_ frame: CGRect) {
        guard viewportWidth > 0, frame.width > 0 else { return }
        let inset = BSSpacing.roomy
        let delta: CGFloat
        if frame.minX < inset {
            delta = frame.minX - inset
        } else if frame.maxX > viewportWidth - inset {
            delta = frame.maxX - (viewportWidth - inset)
        } else {
            return
        }
        withAnimation(BSListeningTokens.selectionAnimation) {
            scrollPosition.scrollTo(x: max(0, scrollOffset + delta))
        }
    }
}
