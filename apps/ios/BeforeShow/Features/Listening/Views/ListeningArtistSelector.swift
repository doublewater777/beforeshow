import SwiftUI

private struct ListeningArtistSelectorItem: View {
    let artist: ListeningBrowseArtist
    let isSelected: Bool
    let onSelect: (CGRect) -> Void
    let onConnect: () -> Void
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            if artist.isConnected {
                onSelect(frame)
            } else {
                onConnect()
            }
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
        .accessibilityHint(artist.isConnected ? "" : BSLocalization.text("轻点连接"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ListeningArtistSelector: View {
    let artists: [ListeningBrowseArtist]
    let selection: ListeningBrowseState.Scope
    let select: (ListeningBrowseState.Scope) -> Void
    let onConnect: (Int, String) -> Void
    @State private var viewportWidth: CGFloat = 0
    @State private var allFrame: CGRect = .zero

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: BSSpacing.sm) {
                    allItem {
                        select(.all)
                        revealIfNeeded("all", frame: allFrame, proxy: proxy)
                    }
                        .id("all")
                    ForEach(artists) { artist in
                        ListeningArtistSelectorItem(
                            artist: artist,
                            isSelected: artist.isConnected && selection == .artist(artist.id),
                            onSelect: { frame in
                                select(.artist(artist.id))
                                revealIfNeeded(artist.id, frame: frame, proxy: proxy)
                            },
                            onConnect: { onConnect(artist.slotIndex, artist.name) }
                        )
                        .id(artist.id)
                    }
                }
            }
            .frame(height: BSLayout.minTouchTarget)
            .padding(.top, BSSpacing.sm)
            .coordinateSpace(name: "artistSelectorViewport")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        }
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

    private func revealIfNeeded(_ id: String, frame: CGRect, proxy: ScrollViewProxy) {
        guard viewportWidth > 0, frame.width > 0 else { return }
        let anchor: UnitPoint
        if frame.minX < 0 {
            anchor = .topLeading
        } else if frame.maxX > viewportWidth {
            anchor = UnitPoint(x: 1, y: 0)
        } else {
            return
        }
        withAnimation(BSListeningTokens.selectionAnimation) {
            proxy.scrollTo(id, anchor: anchor)
        }
    }
}
