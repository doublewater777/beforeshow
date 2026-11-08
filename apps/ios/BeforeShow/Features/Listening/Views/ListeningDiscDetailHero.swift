import SwiftUI

/// The cover on its own, then the credits set like Now Playing: caps artist over a serif title.
struct ListeningDiscDetailHero: View {
    let disc: ListeningDisc
    let show: Show?
    let artistLinks: [ListeningDiscArtistLink]
    let metadata: String
    let isLoaded: Bool
    let isPlaying: Bool
    let containsHeardSongs: Bool

    private var size: CGFloat { BSListeningTokens.detailArtwork }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.lg) {
            ListeningDiscCover(disc: disc, show: show)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 26, y: 18)
                .frame(maxWidth: .infinity)
                .padding(.top, BSSpacing.md)

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                HStack(spacing: BSSpacing.sm) {
                    ListeningDiscArtistCredits(links: artistLinks)
                    if isLoaded {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(BSColor.Stage.accent.opacity(isPlaying ? 1 : 0.6))
                            .accessibilityLabel(ListeningCopy.text(isPlaying ? "播放中" : "暂停"))
                            .accessibilityIdentifier("listening.loadedDiscStatus")
                    }
                }
                Text(disc.title)
                    .font(ListeningOverviewStyle.serif(32))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("listening.discDetail.title")
                HStack(spacing: BSSpacing.xs) {
                    Text(metadata)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                    if containsHeardSongs {
                        Image(systemName: "checkmark.seal.fill")
                            .font(BSListeningTokens.badge)
                            .foregroundStyle(BSColor.Stage.muted)
                            .accessibilityLabel(BSLocalization.text("包含听过的歌曲"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
