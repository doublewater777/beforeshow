import SwiftUI

/// The resident mini player with nothing loaded.
struct ListeningEmptyMiniPlayer: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                ListeningMiniArtwork(artwork: nil, size: 34, isHighlighted: isSelected)
                Text(ListeningCopy.text("未在播放"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textTertiary)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .padding(.trailing, 4)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: ListeningBottomBarLayout.tabSize)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BeforeShowTab.listen.localizedTitle)
        .accessibilityIdentifier("root.tab.listen")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Square album artwork in the mini player, the way Apple Music shows it.
struct ListeningMiniArtwork: View {
    let artwork: UIImage?
    let size: CGFloat
    var isHighlighted: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    BSColor.Stage.surfaceRaised
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(isHighlighted ? BSColor.Stage.accent : BSColor.Stage.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(isHighlighted ? BSColor.Stage.accent.opacity(0.35) : BSColor.Stage.border, lineWidth: 0.5))
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}
