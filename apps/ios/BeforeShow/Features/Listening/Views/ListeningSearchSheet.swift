import SwiftUI

/// 听搜索：在当前现场唱片柜里找唱片与歌曲。结果 push 进唱片详情，返回时保留关键词（系统搜索模式）。
struct ListeningSearchSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var results: (discs: [ListeningSearchResult], tracks: [ListeningSearchResult]) {
        ListeningSearch.results(for: query, in: room.discs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let results = results
                    if ArtistNameMatching.normalized(query).isEmpty {
                        message(icon: "magnifyingglass", title: BSLocalization.text("搜索唱片与歌曲"),
                                detail: BSLocalization.text("在当前现场的唱片柜里找唱片名、艺人或歌名。"))
                    } else if results.discs.isEmpty && results.tracks.isEmpty {
                        message(icon: "music.note", title: BSLocalization.text("没有找到匹配的唱片或歌曲"),
                                detail: BSLocalization.text("换个关键词试试"))
                    } else {
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
            .bsSearchFocused($isSearchFocused)
            .onAppear { isSearchFocused = true }
            .navigationDestination(for: String.self) { resultID in
                let results = results
                if let result = (results.discs + results.tracks).first(where: { $0.id == resultID }) {
                    ListeningDiscDetailView(
                        room: room, disc: result.disc,
                        focusTrackID: result.focusTrackID,
                        dismissPresentation: { dismiss() }
                    )
                }
            }
        }
        .tint(BSColor.Stage.foreground)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ListeningSearchResult]) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(BSListeningTokens.caption.weight(.semibold))
                .foregroundStyle(BSColor.Stage.muted)
                .padding(.top, BSSpacing.lg)
                .padding(.bottom, BSSpacing.xs)
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
