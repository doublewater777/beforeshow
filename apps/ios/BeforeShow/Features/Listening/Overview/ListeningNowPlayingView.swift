import SwiftUI

struct ListeningNowPlayingView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.dismiss) private var dismiss

    private var disc: ListeningDisc? { room.deck.currentDisc }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSSpacing.lg) {
                    if let track = room.track {
                        ListeningArtwork(url: track.artworkURL ?? disc?.artworkURL, title: track.title)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
                            .padding(.horizontal, BSSpacing.lg)
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            artistName(track)
                            Text(track.title).font(ListeningOverviewStyle.serif(32)).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        progress
                        controls
                    }
                    if let disc, disc.tracks.count > 1 {
                        trackList(disc)
                    }
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.bottom, BSSpacing.xl)
            }
            .background {
                ZStack {
                    BSColor.Stage.background
                    ListeningArtwork(url: room.track?.artworkURL ?? disc?.artworkURL, title: "")
                        .blur(radius: 70)
                        .opacity(0.45)
                }
                .ignoresSafeArea()
            }
            .navigationTitle(disc?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
            }
        }
        .foregroundStyle(BSColor.Stage.foreground)
    }

    @ViewBuilder
    private func artistName(_ track: ListeningDiscTrack) -> some View {
        let label = Text(track.artistName)
            .font(ListeningOverviewStyle.caps(13)).tracking(2).textCase(.uppercase)
            .foregroundStyle(BSColor.Stage.accent)
            .lineLimit(1)
        if let artist = room.browseArtists.first(where: { $0.isConnected && $0.name == track.artistName }) {
            NavigationLink {
                ListeningArtistPage(room: room, artistID: artist.id, show: show)
            } label: {
                HStack(spacing: BSSpacing.xs) {
                    label
                    Image(systemName: "chevron.right")
                        .font(ListeningOverviewStyle.badgeGlyph)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listening.nowPlaying.artist")
        } else {
            label
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let duration = room.deck.duration ?? 0
            let elapsed = min(room.elapsed, duration)
            VStack(spacing: BSSpacing.xs) {
                GeometryReader { proxy in
                    Capsule().fill(Color.white.opacity(0.14))
                        .overlay(alignment: .leading) {
                            Capsule().fill(BSColor.Stage.accent)
                                .frame(width: duration > 0 ? proxy.size.width * elapsed / duration : 0)
                        }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.clock(elapsed))
                    Spacer()
                    Text(Self.clock(duration))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(BSColor.Stage.muted)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: BSSpacing.xl) {
            Button { room.perform(.previous) } label: {
                Image(systemName: "backward.fill").font(.system(size: 24)).frame(width: 56, height: 56)
            }
            Button { room.perform(.playPause) } label: {
                Image(systemName: room.display.player.showsPauseControl ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(BSColor.Stage.background)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(BSColor.Stage.foreground))
            }
            Button { room.perform(.next) } label: {
                Image(systemName: "forward.fill").font(.system(size: 24)).frame(width: 56, height: 56)
            }
        }
        .buttonStyle(.plain)
    }

    private func trackList(_ disc: ListeningDisc) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(disc.tracks.enumerated()), id: \.element.id) { index, song in
                let isCurrent = song.id == room.track?.id
                Button { room.playFromSleeve(disc, songID: song.id) } label: {
                    HStack(spacing: BSSpacing.compact) {
                        Group {
                            if isCurrent {
                                Image(systemName: "waveform").foregroundStyle(BSColor.Stage.accent)
                            } else {
                                Text(verbatim: "\(index + 1)").foregroundStyle(BSColor.Stage.muted)
                            }
                        }
                        .font(BSListeningTokens.rowNumber)
                        .frame(width: BSListeningTokens.rowAccessory)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? BSColor.Stage.accent : BSColor.Stage.foreground)
                                .lineLimit(1)
                            if song.artistName != room.track?.artistName || disc.origin != .album {
                                Text(song.artistName).font(BSListeningTokens.caption)
                                    .foregroundStyle(BSColor.Stage.muted).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, BSSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
