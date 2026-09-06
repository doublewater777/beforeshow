import SwiftUI

struct ListeningWantedButton: View {
    @Bindable var room: ListeningRoomCoordinator
    let songID: String
    var body: some View {
        Button { room.toggleWanted(songID) } label: {
            Label(BSLocalization.text("想现场听"), systemImage: room.wantedSongIDs.contains(songID) ? "heart.fill" : "heart")
                .font(BSFont.caption).foregroundStyle(room.wantedSongIDs.contains(songID) ? BSColor.Stage.accent : BSColor.Stage.muted)
                .frame(minHeight: BSLayout.minTouchTarget)
        }.buttonStyle(.plain)
            .accessibilityValue(BSLocalization.text(room.wantedSongIDs.contains(songID) ? "已选择" : "未选择"))
    }
}

struct ListeningDiscDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    HStack {
                        Spacer()
                        ListeningArtwork(url: disc.artworkURL, title: disc.title)
                            .frame(width: 220, height: 220)
                            .overlay(Rectangle().stroke(BSColor.borderProminent))
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 16)
                        Spacer()
                    }.padding(.top, BSSpacing.lg)
                    VStack(spacing: BSSpacing.sm) {
                        Text(disc.title).font(BSFont.V3.title1).multilineTextAlignment(.center)
                        Text(Array(Set(disc.tracks.map(\.artistName))).sorted().joined(separator: " / "))
                            .font(BSFont.body).foregroundStyle(BSColor.Stage.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                    Button { room.loadDisc(disc); dismiss() } label: {
                        Label(BSLocalization.text("装入 CD"), systemImage: "opticaldisc")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(BSPrimaryButtonStyle()).disabled(room.busy)
                    HStack {
                        Text(BSLocalization.text("曲目")).font(BSFont.headline)
                        Spacer()
                        Text(String(format: "%02d", disc.tracks.count)).font(BSFont.V3.caption).foregroundStyle(BSColor.Stage.dim)
                    }.padding(.top, BSSpacing.sm)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(disc.tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(alignment: .top, spacing: BSSpacing.md) {
                                Text(String(format: "%02d", index + 1)).font(BSFont.caption).monospacedDigit()
                                    .foregroundStyle(BSColor.Stage.dim).frame(width: 24).padding(.top, BSSpacing.xs)
                                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                                    Text(track.title).font(BSFont.headline)
                                    Text(track.artistName).font(BSFont.V3.small).foregroundStyle(BSColor.Stage.muted)
                                    Text(capabilityText(track)).font(BSFont.V3.caption).foregroundStyle(BSColor.Stage.dim)
                                    ListeningWantedButton(room: room, songID: track.id)
                                }
                                Spacer(minLength: 0)
                                if room.familiarSongIDs.contains(track.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BSColor.Stage.success)
                                        .accessibilityLabel(BSLocalization.text("已熟悉"))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, BSSpacing.md)
                                .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.border).frame(height: 1) }
                        }
                    }
                }.padding(.horizontal, BSSpacing.lg).padding(.bottom, BSSpacing.xl)
            }
            .background(BSColor.Stage.background)
            .foregroundStyle(BSColor.Stage.foreground)
            .navigationTitle(BSLocalization.text("唱片柜")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(BSLocalization.text("完成")) { dismiss() } } }
        }.tint(BSColor.Stage.accent).presentationDragIndicator(.visible)
    }
    private func capabilityText(_ track: ListeningDiscTrack) -> String {
        switch room.capability(for: track) {
        case .fullPlayback: BSLocalization.text("完整播放")
        case .previewOnly: BSLocalization.text("试听 · 不计入熟悉度")
        case .metadataOnly: BSLocalization.text("仅歌曲信息")
        case .unavailable: BSLocalization.text("暂不可播放")
        }
    }
}
