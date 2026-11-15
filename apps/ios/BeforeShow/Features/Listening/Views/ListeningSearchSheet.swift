import SwiftUI

/// 听搜索：在当前现场唱片柜里找唱片与歌曲。结果 push 进唱片详情，返回时保留关键词（系统搜索模式）。
/// 未输入时按唱片柜分组列出全部唱片，未连接的艺人可直接在此连接。
struct ListeningSearchSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: (discs: [ListeningSearchResult], tracks: [ListeningSearchResult]) {
        ListeningSearch.results(for: query, in: room.discs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let results = results
                    let artists = ListeningSearch.artists(for: query, in: room.browseArtists)
                    if ArtistNameMatching.normalized(query).isEmpty {
                        let groups = room.rackGroups
                        if groups.isEmpty {
                            message(icon: "magnifyingglass", title: BSLocalization.text("搜索唱片与歌曲"),
                                    detail: BSLocalization.text("在当前现场的唱片柜里找唱片名、艺人或歌名。"))
                        } else {
                            ForEach(groups) { browseGroup($0) }
                        }
                    } else if artists.isEmpty && results.discs.isEmpty && results.tracks.isEmpty {
                        message(icon: "music.note", title: BSLocalization.text("没有找到匹配的唱片或歌曲"),
                                detail: BSLocalization.text("换个关键词试试"))
                    } else {
                        artistSection(artists)
                        section(BSLocalization.text("唱片"), results.discs)
                        section(BSLocalization.text("歌曲"), results.tracks)
                    }
                }
                .padding(.horizontal, BSSpacing.roomy)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(BSColor.Stage.background.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("搜索唱片与歌曲"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭")) { dismiss() }
            }
            .searchable(text: $query, prompt: Text(BSLocalization.text("唱片、艺人或歌名")))
            .navigationDestination(for: String.self) { resultID in
                if let result = destination(for: resultID) {
                    ListeningDiscDetailView(
                        room: room, disc: result.disc,
                        focusTrackID: result.focusTrackID,
                        dismissPresentation: { dismiss() }
                    )
                }
            }
            .navigationDestination(for: ArtistReference.self) { reference in
                ArtistProfileView(reference: reference, show: room.show, room: room)
            }
            .navigationDestination(for: ListeningArtistConnectRoute.self) { route in
                ListeningArtistMatchSheet(room: room, slotIndex: route.slotIndex, query: route.name, isPushed: true)
            }
        }
        .tint(BSColor.Stage.foreground)
        .preferredColorScheme(.dark)
    }

    private func destination(for resultID: String) -> ListeningSearchResult? {
        let results = results
        return (results.discs + results.tracks).first { $0.id == resultID }
            ?? room.discs.lazy.map { ListeningSearchResult(disc: $0, focusTrack: nil) }.first { $0.id == resultID }
    }

    @ViewBuilder
    private func browseGroup(_ group: ListeningRackGroup) -> some View {
        if case let .artist(id, _, true) = group.kind,
           let artist = room.browseArtists.first(where: { $0.id == id }) {
            NavigationLink(value: ArtistReference(browseArtist: artist, show: room.show)) {
                sectionTitle(group.name, showsChevron: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listening.search.browseArtist")
        } else {
            sectionTitle(group.name)
        }
        if case let .artist(_, slotIndex, false) = group.kind {
            NavigationLink(value: ListeningArtistConnectRoute(slotIndex: slotIndex, name: group.name)) {
                artistRow(artworkURL: group.artworkURL, name: group.name,
                          title: BSLocalization.text("连接艺人"), detail: BSLocalization.text("尚未匹配 Apple Music 艺人"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listening.search.connectArtist")
        }
        ForEach(group.discs) { disc in
            let item = ListeningSearchResult(disc: disc, focusTrack: nil)
            NavigationLink(value: item.id) { row(item) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listening.search.browseDisc")
        }
    }

    private func sectionTitle(_ title: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: BSSpacing.xs) {
            Text(title)
            if showsChevron { Image(systemName: "chevron.right") }
        }
        .font(BSListeningTokens.caption.weight(.semibold))
        .foregroundStyle(BSColor.Stage.muted)
        .padding(.top, BSSpacing.lg)
        .padding(.bottom, BSSpacing.xs)
    }

    @ViewBuilder
    private func artistSection(_ artists: [ListeningBrowseArtist]) -> some View {
        if !artists.isEmpty {
            sectionTitle(BSLocalization.text("艺人"))
            ForEach(artists) { artist in
                Group {
                    if artist.isConnected {
                        NavigationLink(value: ArtistReference(browseArtist: artist, show: room.show)) {
                            artistRow(artworkURL: artist.artworkURL, name: artist.name, title: artist.name, detail: nil)
                        }
                    } else {
                        NavigationLink(value: ListeningArtistConnectRoute(slotIndex: artist.slotIndex, name: artist.name)) {
                            artistRow(artworkURL: artist.artworkURL, name: artist.name, title: artist.name,
                                      detail: BSLocalization.text("尚未匹配 Apple Music 艺人"))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listening.search.artist")
            }
        }
    }

    private func artistRow(artworkURL: URL?, name: String, title: String, detail: String?) -> some View {
        HStack(spacing: BSSpacing.sm) {
            ListeningArtistArtwork(url: artworkURL, name: name, size: 44)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BSFont.body)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.dim)
        }
        .padding(.vertical, BSSpacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ListeningSearchResult]) -> some View {
        if !items.isEmpty {
            sectionTitle(title)
            ForEach(items) { item in
                NavigationLink(value: item.id) { row(item) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("listening.search.result")
            }
        }
    }

    private func row(_ item: ListeningSearchResult) -> some View {
        HStack(spacing: BSSpacing.sm) {
            Group {
                if let track = item.focusTrack {
                    ListeningArtwork(url: track.artworkURL ?? item.disc.artworkURL, title: track.title)
                } else {
                    ListeningDiscCover(disc: item.disc, show: room.show)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.focusTrack?.title ?? item.disc.title)
                    .font(BSFont.body)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(subtitle(item))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BSSpacing.xs)
        .contentShape(Rectangle())
    }

    private func subtitle(_ item: ListeningSearchResult) -> String {
        if let track = item.focusTrack {
            return BSLocalization.format("%1$@ · %2$@", track.artistName, item.disc.title)
        }
        return item.disc.artistNames.joined(separator: " / ")
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: BSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(BSColor.Stage.dim)
            Text(title)
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.muted)
            Text(detail)
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }
}

/// 搜索页里连接未匹配艺人的 push 目标。
struct ListeningArtistConnectRoute: Hashable {
    let slotIndex: Int
    let name: String
}
