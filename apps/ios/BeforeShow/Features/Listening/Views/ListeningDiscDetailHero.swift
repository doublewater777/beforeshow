import SwiftUI

struct ListeningDiscDetailHero: View {
    let disc: ListeningDisc
    let show: Show?
    let artists: String
    let metadata: String
    let isLoaded: Bool
    let isPlaying: Bool
    let containsHeardSongs: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.lg) {
            ZStack(alignment: .leading) {
                ListeningPeekingDisc(disc: disc, size: BSListeningTokens.detailArtwork * BSListeningTokens.detailDiscFraction)
                    .offset(x: BSListeningTokens.detailArtwork * (1 - BSListeningTokens.detailDiscFraction + BSListeningTokens.detailDiscReveal))
                    .opacity(isLoaded ? 0 : 1)
                    .animation(reduceMotion ? nil : BSListeningTokens.selectionAnimation, value: isLoaded)
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: BSListeningTokens.detailArtwork, height: BSListeningTokens.detailArtwork)
            }
            .frame(width: BSListeningTokens.detailArtwork * (1 + BSListeningTokens.detailDiscReveal),
                   height: BSListeningTokens.detailArtwork, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BSSpacing.lg)

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                if isLoaded {
                    ListeningDiscStatusBadge(isPlaying: isPlaying)
                        .accessibilityIdentifier("listening.loadedDiscStatus")
                }
                Text(disc.title)
                    .font(BSListeningTokens.detailTitle)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !artists.isEmpty {
                    Text(artists)
                        .font(BSFont.body)
                        .foregroundStyle(BSColor.Stage.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: BSSpacing.sm) {
                    Text(metadata)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if containsHeardSongs {
                        Image(systemName: "checkmark.seal.fill")
                            .font(BSListeningTokens.badge)
                            .foregroundStyle(BSColor.Stage.accent)
                            .accessibilityLabel(BSLocalization.text("包含听过的歌曲"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
