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
                    shelf(ListeningDiscPickFilter.albums.title, rest.filter(ListeningDiscPickFilter.albums.includes))
                    shelf(ListeningDiscPickFilter.singlesAndEPs.title, rest.filter(ListeningDiscPickFilter.singlesAndEPs.includes))
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
                .frame(height: ListeningOverviewStyle.artistHeroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, BSColor.Stage.background], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: BSSpacing.md) {
                Text(artist.name)
                    .font(ListeningOverviewStyle.serif(44))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if !artist.albums.isEmpty { shuffleButton(artist) }
            }
            .padding(.horizontal, BSSpacing.roomy)
        }
        .frame(height: ListeningOverviewStyle.artistHeroHeight)
    }

    private func latestAlbum(_ disc: ListeningDisc) -> some View {
        HStack(alignment: .bottom, spacing: BSSpacing.md) {
            NavigationLink { ListeningPushedDiscDetail(room: room, disc: disc) } label: {
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: ListeningOverviewStyle.featuredCover, height: ListeningOverviewStyle.featuredCover)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                NavigationLink { ListeningPushedDiscDetail(room: room, disc: disc) } label: {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(disc.title).font(ListeningOverviewStyle.serif(24)).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(ListeningReleaseMeta.yearAndTrackCount(disc))
                            .font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                    }
                }
                .buttonStyle(.plain)
                Button { play(disc) } label: {
                    Label(BSLocalization.text("播放"), systemImage: room.isOnDeckAndPlaying(disc) ? "waveform" : "play.fill")
                        .font(ListeningOverviewStyle.buttonLabel)
                        .foregroundStyle(BSColor.Stage.background)
                        .padding(.horizontal, BSSpacing.md)
                        .frame(height: ListeningOverviewStyle.pillHeight)
                        .background(Capsule().fill(BSColor.Stage.foreground))
                }
                .buttonStyle(.plain)
                .padding(.top, BSSpacing.xs)
                .accessibilityIdentifier("listening.artist.playLatest")
            }
        }
        .padding(.horizontal, BSSpacing.roomy)
    }

    /// Plays the artist's records whole, one after another, in an order you don't get to see.
    private func shuffleButton(_ artist: ListeningBrowseArtist) -> some View {
        let isOn = room.isShuffling(artist.id)
        return Button {
            room.shuffleDiscography(of: artist.id, discs: artist.albums)
        } label: {
            Label(BSLocalization.text(isOn ? "换一张" : "随机播放"), systemImage: isOn ? "waveform" : "shuffle")
                .font(ListeningOverviewStyle.buttonLabel)
                .foregroundStyle(BSColor.Stage.background)
                .padding(.horizontal, BSSpacing.md)
                .frame(height: ListeningOverviewStyle.pillHeight)
                .background(Capsule().fill(BSColor.Stage.foreground))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityIdentifier("listening.artist.shuffle")
    }

    private func play(_ disc: ListeningDisc) {
        room.play(disc)
    }
}

private struct ListeningArtistReleaseCard: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    let show: Show
    private static let width = ListeningOverviewStyle.releaseCard

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
                                .frame(width: ListeningOverviewStyle.badge, height: ListeningOverviewStyle.badge)
                                .background(Circle().fill(BSColor.Stage.foreground))
                                .padding(BSSpacing.xs)
                        }
                    }
                Text(disc.title)
                    .font(ListeningOverviewStyle.itemTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(ListeningReleaseMeta.yearAndTrackCount(disc)).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
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
