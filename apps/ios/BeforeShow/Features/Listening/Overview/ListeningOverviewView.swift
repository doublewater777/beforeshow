import SwiftUI

enum ListeningOverviewSheet: Identifiable {
    case artist(String)

    var id: String {
        switch self {
        case let .artist(id): "artist-\(id)"
        }
    }
}

struct ListeningOverviewView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    let onOpenSheet: (ListeningOverviewSheet) -> Void
    let onMatchArtist: (ListeningBrowseArtist) -> Void
    let onOpenPick: (ListeningDisc?) -> Void
    /// Stays put across tab and Watch switches; changes when the user stops on another album in the feed.
    @Binding var pickPreview: ListeningDisc?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: BSSpacing.xl) {
                Color.clear.frame(height: BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding)
                ListeningLineupPoster(room: room, show: show, onArtist: openArtist)
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
            if ListeningPickCardPolicy.needsNewDraw(current: pickPreview, candidateIDs: ids) { pickPreview = drawPreview() }
        }
    }

    private func openArtist(_ artist: ListeningBrowseArtist) {
        artist.isConnected ? onOpenSheet(.artist(artist.id)) : onMatchArtist(artist)
    }

    private func drawPreview() -> ListeningDisc? {
        ListeningDiscPickPolicy.pick(showID: show.id, scopeKey: ListeningDiscPickPolicy.showScopeKey,
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
                .font(ListeningOverviewStyle.headerTitle)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Circle().fill(ListeningOverviewStyle.buttonFill))
        }
        .padding(BSSpacing.md)
        .background(RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous).fill(ListeningOverviewStyle.cardFill))
        .contentShape(Rectangle())
    }
}

private struct ListeningPlaylistTile: View {
    let disc: ListeningDisc
    let show: Show
    let isCurrent: Bool

    var body: some View {
        let size = ListeningOverviewStyle.playlistTile.width
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            ListeningDiscCover(disc: disc, show: show)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .font(ListeningOverviewStyle.badgeGlyph)
                            .symbolEffect(.variableColor.iterative)
                            .foregroundStyle(BSColor.Stage.background)
                            .frame(width: ListeningOverviewStyle.badge, height: ListeningOverviewStyle.badge)
                            .background(Circle().fill(BSColor.Stage.foreground))
                            .padding(BSSpacing.xs)
                    }
                }
            Text(ListeningCopy.format("%d 首", disc.tracks.count))
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.muted)
        }
        .frame(width: size, alignment: .leading)
    }
}
