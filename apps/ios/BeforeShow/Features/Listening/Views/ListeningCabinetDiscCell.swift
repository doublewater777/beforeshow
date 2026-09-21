import SwiftUI

struct ListeningCabinetDiscCell: View {
    let disc: ListeningDisc
    let show: Show?
    let presentation: ListeningDiscPresentation
    let isLoaded: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: BSListeningTokens.shelfItemSpacing) {
                ListeningDiscCover(disc: disc, show: show)
                    .overlay(alignment: .bottomTrailing) {
                        if isLoaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BSColor.Stage.accent, .black)
                                .padding(BSSpacing.xs)
                        }
                    }
                Text(disc.title)
                    .font(BSListeningTokens.captionMedium)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !presentation.canLoad {
                    Text(presentation.statusText)
                        .font(.caption2)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(2)
                }
            }
        }
        .disabled(!presentation.canLoad)
        .buttonStyle(BSListeningPressStyle())
        .accessibilityLabel(disc.title)
        .accessibilityValue(isLoaded ? BSLocalization.text("已放入") : "")
        .accessibilityHint(presentation.canLoad ? BSLocalization.text("放入") : presentation.statusText)
        .accessibilityIdentifier("listening.selectDisc.\(disc.id)")
    }
}
