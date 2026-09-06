import SwiftUI

/// The physical player remains the hero; this card presents its current record.
struct ListeningSongCardView: View {
    @Bindable var room: ListeningRoomCoordinator
    let openArtist: () -> Void
    @State private var seekTime: Double = 0
    @State private var seeking = false
    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            if let track = room.track {
                HStack(alignment: .top, spacing: BSSpacing.md) {
                    ListeningArtwork(url: track.artworkURL, title: room.mechanism.disc?.title ?? track.title)
                        .frame(width: 56, height: 56).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(track.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        Button(track.artistName, action: openArtist).font(.subheadline).frame(minHeight: 44)
                            .accessibilityHint(BSLocalization.text("打开艺人详情"))
                        Text(room.capabilityTitle).font(.caption).foregroundStyle(BSColor.Stage.muted)
                        if let id = room.currentArtistID, let artist = room.artistPresentation(id) {
                            if artist.top.contains(where: { $0.id == track.id }) { Text("Apple Music · \(BSLocalization.text("热门"))").font(.caption2) }
                            if let tier = artist.tier { Text(BSLocalization.text(tier.localizationKey)).font(.caption).foregroundStyle(BSColor.Stage.muted) }
                        }
                        if room.familiarSongIDs.contains(track.id) {
                            Label(BSLocalization.text("已熟悉"), systemImage: "checkmark").font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let duration = track.duration, duration.isFinite, duration > 0, room.capability(for: track) == .fullPlayback {
                    Slider(value: Binding(get: { seeking ? seekTime : min(room.elapsed, duration) }, set: { seekTime = $0 }),
                           in: 0...duration, onEditingChanged: { editing in
                        seeking = editing
                        if !editing { room.seek(seekTime) }
                    }).tint(BSColor.Stage.muted).accessibilityLabel(BSLocalization.text("播放进度"))
                }
                ListeningWantedButton(room: room, songID: track.id)
                if let error = room.playbackError {
                    HStack { Text(error).font(.caption); Button(BSLocalization.text("重试")) { room.playPause() } }
                }
                if let next = room.nextTrack {
                    HStack {
                        ListeningArtwork(url: next.artworkURL, title: next.title).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text(BSLocalization.text(next.artistName == track.artistName ? "接下来" : "下一位") + " · " + next.artistName).font(.caption).foregroundStyle(BSColor.Stage.muted)
                            Text(next.title).font(.subheadline)
                        }
                    }.accessibilityElement(children: .combine)
                }
            } else {
                Text("\(room.mechanism.configuration.brand) \(room.mechanism.configuration.model)").font(.headline)
                Text(BSLocalization.text("装入 CD")).font(.caption).foregroundStyle(BSColor.Stage.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: BSLocalization.text("下一曲")) { room.skip(1) }
            .accessibilityAction(named: BSLocalization.text("上一曲")) { room.skip(-1) }
    }
}
