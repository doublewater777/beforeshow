import SwiftUI

enum ListeningOverviewStyle {
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif).italic() }
    static func caps(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .default).width(.condensed) }
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    static let posterHeight: CGFloat = 420
    static let pickCover: CGFloat = 104
    static let playlistTile = CGSize(width: 128, height: 92)
}

enum ListeningOverviewSheet: Identifiable {
    case artist(String)
    case lineup

    var id: String {
        switch self {
        case let .artist(id): "artist-\(id)"
        case .lineup: "lineup"
        }
    }
}

struct ListeningOverviewView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    let onOpenSheet: (ListeningOverviewSheet) -> Void
    let onMatchArtist: (ListeningBrowseArtist) -> Void
    let onOpenPick: (ListeningDisc?) -> Void
    @State private var pickPreview: ListeningDisc?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: BSSpacing.xl) {
                ListeningLineupPoster(room: room, show: show, onArtist: openArtist) {
                    onOpenSheet(.lineup)
                }
                if room.showsRack {
                    pickSection
                    playlistSection
                } else {
                    ListeningOverviewStatus(room: room, onMatchArtist: onMatchArtist)
                        .padding(.horizontal, BSSpacing.roomy)
                }
            }
            .padding(.bottom, BSSpacing.xl)
        }
        .onChange(of: room.pickCandidates(filter: .all).map(\.id), initial: true) { _, ids in
            if pickPreview.map({ ids.contains($0.id) }) != true { pickPreview = drawPreview() }
        }
    }

    private func openArtist(_ artist: ListeningBrowseArtist) {
        artist.isConnected ? onOpenSheet(.artist(artist.id)) : onMatchArtist(artist)
    }

    private func drawPreview() -> ListeningDisc? {
        ListeningDiscPickPolicy.pick(showID: show.id, scopeKey: ListeningDiscPickPolicy.scopeKey(for: .all),
                                     candidates: room.pickCandidates(filter: .all))
    }

    @ViewBuilder
    private var pickSection: some View {
        let count = room.pickCandidates(filter: .all).count
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            sectionHeader(ListeningCopy.text("帮我挑一张"),
                          trailing: count > 0 ? ListeningCopy.format("%d 张唱片", count) : nil)
            Button { onOpenPick(pickPreview) } label: {
                ListeningPickEntryCard(disc: pickPreview, show: show)
            }
            .buttonStyle(.plain)
            .disabled(pickPreview == nil)
            .accessibilityIdentifier("listening.overview.pick")
        }
        .padding(.horizontal, BSSpacing.roomy)
    }

    @ViewBuilder
    private var playlistSection: some View {
        if !room.compilationDiscs.isEmpty {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                sectionHeader(ListeningCopy.text("本场歌单"), trailing: nil)
                    .padding(.horizontal, BSSpacing.roomy)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BSSpacing.sm) {
                        ForEach(room.compilationDiscs) { disc in
                            Button { room.browser.open(disc) } label: {
                                ListeningPlaylistTile(disc: disc, show: show, isCurrent: room.isOnDeckAndPlaying(disc))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("listening.overview.playlist.\(disc.id)")
                        }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(ListeningOverviewStyle.sectionTitle)
            Spacer()
            if let trailing {
                Text(trailing).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
            }
        }
    }
}

private struct ListeningPickEntryCard: View {
    let disc: ListeningDisc?
    let show: Show

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            Group {
                if let disc { ListeningDiscCover(disc: disc, show: show) } else { BSColor.Stage.surfaceRaised }
            }
            .frame(width: ListeningOverviewStyle.pickCover, height: ListeningOverviewStyle.pickCover)
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                if let disc {
                    Text(disc.artistNames.first ?? "")
                        .font(ListeningOverviewStyle.caps(12)).tracking(2).textCase(.uppercase)
                        .foregroundStyle(BSColor.Stage.accent)
                    Text(disc.title).font(ListeningOverviewStyle.serif(26)).lineLimit(1)
                    Text(ListeningCopy.format("%d 首", disc.tracks.count))
                        .font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .padding(BSSpacing.md)
        .background(RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
    }
}

private struct ListeningPlaylistTile: View {
    let disc: ListeningDisc
    let show: Show
    let isCurrent: Bool

    var body: some View {
        let size = ListeningOverviewStyle.playlistTile
        ZStack(alignment: .bottomLeading) {
            ListeningDiscCover(disc: disc, show: show)
                .frame(width: size.width, height: size.width)
                .frame(width: size.width, height: size.height)
                .blur(radius: 14)
                .opacity(0.75)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(disc.title).font(ListeningOverviewStyle.serif(22)).lineLimit(1)
                Text(ListeningCopy.format("%d 首", disc.tracks.count))
                    .font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.foreground.opacity(0.7))
            }
            .padding(BSSpacing.sm)
        }
        .frame(width: size.width, height: size.height)
        .background(BSColor.Stage.surfaceRaised)
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BSColor.Stage.background)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(BSColor.Stage.foreground))
                    .padding(BSSpacing.xs)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
    }
}

@MainActor extension ListeningRoomCoordinator {
    /// Any disc on the deck counts, including artist releases outside the show's own shelf.
    func isOnDeckAndPlaying(_ disc: ListeningDisc) -> Bool {
        display.player.isPlaybackActive && mechanism.hasDisc && mechanism.disc?.id == disc.id
    }

    func pickCandidates(filter: ListeningDiscPickFilter) -> [ListeningDisc] {
        let candidates = ListeningDiscPickCandidates.discs(in: rackGroups, scope: .all)
            .filter { !$0.tracks.isEmpty && $0.origin == .album && filter.includes($0) }
        let loadable = candidates.filter { discPresentation(for: $0).canLoad }
        return loadable.isEmpty ? candidates : loadable
    }
}
