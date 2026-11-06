import SwiftUI

struct ListeningArtistPage: View {
    @Bindable var room: ListeningRoomCoordinator
    let artistID: String
    let show: Show

    private var artist: ListeningBrowseArtist? { room.browseArtists.first { $0.id == artistID } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let artist {
                let releases = ListeningArtistReleases.newestFirst(artist.albums)
                let featured = ListeningArtistReleases.featured(releases)
                let rest = releases.filter { $0.id != featured?.id }
                VStack(alignment: .leading, spacing: BSSpacing.xl) {
                    hero(artist)
                    if let featured {
                        latestAlbum(featured)
                    }
                    shelf(ListeningCopy.text("专辑"), rest.filter { ListeningArtistReleases.kind($0) == .album })
                    shelf("EP", rest.filter { ListeningArtistReleases.kind($0) == .ep })
                    shelf(ListeningCopy.text("单曲"), rest.filter { ListeningArtistReleases.kind($0) == .single })
                    if releases.isEmpty {
                        if room.artistCatalogStatus[artist.appleMusicArtistID ?? ""] == .loading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            ListeningCatalogStatusView(title: BSLocalization.text("暂时没有找到可翻的唱片"))
                        }
                    }
                }
                .padding(.bottom, BSSpacing.xl)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .foregroundStyle(BSColor.Stage.foreground)
        .task(id: artist?.appleMusicArtistID) {
            if let id = artist?.appleMusicArtistID { room.loadArtistCatalogIfNeeded(id) }
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ discs: [ListeningDisc]) -> some View {
        if !discs.isEmpty {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: title).font(ListeningOverviewStyle.sectionTitle)
                    Spacer()
                    Text(verbatim: "\(discs.count)").font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                }
                .padding(.horizontal, BSSpacing.roomy)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: BSSpacing.compact) {
                        ForEach(discs) { disc in
                            ListeningArtistReleaseCard(room: room, disc: disc, show: show)
                        }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                }
            }
        }
    }

    private func hero(_ artist: ListeningBrowseArtist) -> some View {
        ZStack(alignment: .bottomLeading) {
            ListeningArtwork(url: artist.artworkURL, title: artist.name)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, BSColor.Stage.background], startPoint: .center, endPoint: .bottom)
            Text(artist.name)
                .font(ListeningOverviewStyle.serif(44))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, BSSpacing.roomy)
        }
        .frame(height: 300)
    }

    private func latestAlbum(_ disc: ListeningDisc) -> some View {
        HStack(alignment: .bottom, spacing: BSSpacing.md) {
            NavigationLink { ListeningPushedDiscDetail(room: room, disc: disc) } label: {
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: 132, height: 132)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                NavigationLink { ListeningPushedDiscDetail(room: room, disc: disc) } label: {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(ListeningArtistReleases.displayTitle(disc)).font(ListeningOverviewStyle.serif(24)).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(ListeningArtistReleaseCard.meta(disc))
                            .font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                    }
                }
                .buttonStyle(.plain)
                Button { play(disc) } label: {
                    Label(BSLocalization.text("播放"), systemImage: room.isOnDeckAndPlaying(disc) ? "waveform" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BSColor.Stage.background)
                        .padding(.horizontal, BSSpacing.md)
                        .frame(height: 40)
                        .background(Capsule().fill(BSColor.Stage.foreground))
                }
                .buttonStyle(.plain)
                .padding(.top, BSSpacing.xs)
                .accessibilityIdentifier("listening.artist.playLatest")
            }
        }
        .padding(.horizontal, BSSpacing.roomy)
    }

    private func play(_ disc: ListeningDisc) {
        if !room.isOnDeckAndPlaying(disc) { room.loadPlayableDisc(disc) }
    }
}

private struct ListeningArtistReleaseCard: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    let show: Show
    private static let width: CGFloat = 128

    static func meta(_ disc: ListeningDisc) -> String {
        let count = ListeningCopy.format("%d 首", disc.tracks.count)
        guard let date = disc.releaseDate else { return count }
        return "\(Calendar.current.component(.year, from: date)) · \(count)"
    }

    var body: some View {
        NavigationLink {
            ListeningPushedDiscDetail(room: room, disc: disc)
        } label: {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: Self.width, height: Self.width)
                    .overlay(alignment: .bottomTrailing) {
                        if room.isOnDeckAndPlaying(disc) {
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BSColor.Stage.background)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(BSColor.Stage.foreground))
                                .padding(BSSpacing.xs)
                        }
                    }
                Text(ListeningArtistReleases.displayTitle(disc))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(Self.meta(disc)).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
            }
            .frame(width: Self.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A release pushed inside the artist page; playing from it returns to the artist.
private struct ListeningPushedDiscDetail: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ListeningDiscDetailView(room: room, disc: disc, showsCloseButton: false, dismissPresentation: { dismiss() })
    }
}

struct ListeningLineupList: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    let onMatchArtist: (ListeningBrowseArtist) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var artists: [ListeningBrowseArtist] {
        var seen = Set<String>()
        return room.browseArtists.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ListeningLineupSection.sections(artists, query: query)) { section in
                    Section(section.id) {
                        ForEach(section.artists) { artist in
                            row(artist)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BSColor.Stage.background.ignoresSafeArea())
            .searchable(text: $query, prompt: ListeningCopy.text("搜索艺人"))
            .navigationTitle(ListeningCopy.text("全部艺人"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                ListeningArtistPage(room: room, artistID: id, show: show)
            }
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
            }
        }
        .foregroundStyle(BSColor.Stage.foreground)
    }

    @ViewBuilder
    private func row(_ artist: ListeningBrowseArtist) -> some View {
        let label = HStack(spacing: BSSpacing.compact) {
            ListeningArtwork(url: artist.artworkURL, title: artist.name)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            Text(artist.name)
                .foregroundStyle(artist.isConnected ? BSColor.Stage.foreground : BSColor.Stage.muted)
            Spacer()
        }
        if artist.isConnected {
            NavigationLink(value: artist.id) { label }
                .listRowBackground(Color.clear)
        } else {
            Button { onMatchArtist(artist) } label: { label }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
        }
    }
}
