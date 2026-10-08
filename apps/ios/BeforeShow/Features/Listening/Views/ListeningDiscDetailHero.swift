import SwiftUI

/// The case lifted off the shelf: centred jewel case with its disc slid out, then the credits.
struct ListeningDiscDetailHero: View {
    let disc: ListeningDisc
    let show: Show?
    let artists: String
    let metadata: String
    let isLoaded: Bool
    let isPlaying: Bool
    let containsHeardSongs: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGFloat { BSListeningTokens.detailArtwork }

    var body: some View {
        VStack(spacing: BSSpacing.lg) {
            ZStack {
                ListeningPeekingDisc(disc: disc, size: size * BSListeningTokens.detailDiscFraction)
                    .offset(x: isLoaded ? 0 : size * BSListeningTokens.detailDiscReveal)
                    .opacity(isLoaded ? 0 : 1)
                    .animation(reduceMotion ? nil : BSListeningTokens.selectionAnimation, value: isLoaded)
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: size, height: size)
                    .overlay { ListeningJewelCaseFinish() }
                    .shadow(color: .black.opacity(0.55), radius: 22, y: 16)
            }
            .offset(x: isLoaded ? 0 : -size * BSListeningTokens.detailDiscReveal / 2)
            .frame(maxWidth: .infinity)
            .padding(.top, BSSpacing.lg)

            VStack(spacing: BSSpacing.sm) {
                if isLoaded {
                    ListeningDiscStatusBadge(isPlaying: isPlaying)
                        .accessibilityIdentifier("listening.loadedDiscStatus")
                }
                Text(disc.title)
                    .font(BSListeningTokens.detailTitle)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !artists.isEmpty {
                    Text(artists)
                        .font(BSFont.body)
                        .foregroundStyle(BSColor.Stage.accent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: BSSpacing.xs) {
                    Text(metadata)
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .multilineTextAlignment(.center)
                    if containsHeardSongs {
                        Image(systemName: "checkmark.seal.fill")
                            .font(BSListeningTokens.badge)
                            .foregroundStyle(BSColor.Stage.accent)
                            .accessibilityLabel(BSLocalization.text("包含听过的歌曲"))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
