import SwiftUI

struct ListeningAtmosphere: View {
    let disc: ListeningDisc?
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkColor: Color?

    private var color: Color {
        guard let disc else { return BSColor.Stage.accent }
        if case .compilation = disc.origin { return ListeningSleeveIdentity(disc: disc).color }
        return artworkColor ?? ListeningSleeveIdentity(disc: disc).color
    }

    var body: some View {
        Ellipse()
            .fill(color.opacity(isPlaying ? BSListeningTokens.playingLightOpacity : BSListeningTokens.restingLightOpacity))
            .frame(height: BSListeningTokens.lightHeight)
            .blur(radius: BSListeningTokens.lightBlur)
            .offset(y: BSListeningTokens.lightOffset)
            .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: color)
            .animation(reduceMotion ? nil : .easeInOut(duration: BSListeningTokens.lightDuration), value: isPlaying)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: disc?.artworkURL) {
                artworkColor = nil
                guard let url = disc?.artworkURL,
                      let image = await ShowCoverImageCache.shared.image(from: url),
                      let sampled = await ArtworkColorSampler.color(in: image), !Task.isCancelled else { return }
                artworkColor = Color(uiColor: sampled)
            }
    }
}

struct ListeningCurrentSong: View {
    let room: ListeningRoomCoordinator

    private var stateText: String {
        if room.busy { return BSLocalization.text("加载中…") }
        if let error = room.playbackError { return error }
        switch room.playbackState {
        case .playing: return BSLocalization.text("正在播放")
        case .paused: return BSLocalization.text("已暂停")
        case .finished: return BSLocalization.text("播放结束")
        default: return BSLocalization.text("已停止")
        }
    }

    var body: some View {
        if room.mechanism.position == .seated, let track = room.track {
            VStack(spacing: BSSpacing.xs) {
                Text(track.title).font(BSListeningTokens.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                Text(track.artistName).font(BSListeningTokens.body)
                    .foregroundStyle(BSColor.Stage.muted)
                Text("\(stateText) · \(room.capabilityTitle)")
                    .font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.accent)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("listening.currentSong")
        }
    }
}
