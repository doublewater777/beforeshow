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

    var body: some View {
        ZStack {
            if room.mechanism.position == .seated, let track = room.track {
                VStack(spacing: 3) {
                    Text(track.title).font(BSListeningTokens.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(track.artistName).font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("listening.currentSong")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(minHeight: 46)
        .animation(.easeInOut(duration: 0.25), value: room.track?.id)
        .animation(.easeInOut(duration: 0.25), value: room.mechanism.position)
    }
}
