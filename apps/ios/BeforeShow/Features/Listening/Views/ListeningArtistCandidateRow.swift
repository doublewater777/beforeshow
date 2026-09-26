import SwiftUI

struct ListeningArtistCandidateRow: View {
    let candidate: RecognizedArtist
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: BSSpacing.compact) {
                ListeningArtistArtwork(url: candidate.avatarURL, name: candidate.canonicalName,
                                       size: BSListeningTokens.candidateAvatar)
                    .frame(width: BSListeningTokens.candidateAvatar, height: BSListeningTokens.candidateAvatar)
                    .clipShape(Circle())
                Text(candidate.canonicalName)
                    .font(BSListeningTokens.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(BSListeningTokens.songTitle)
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.Stage.dim)
            }
            .padding(BSSpacing.compact)
            .background(isSelected ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionFillOpacity) : BSColor.Stage.surface,
                        in: RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .strokeBorder(isSelected ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionBorderOpacity) : BSColor.Stage.border,
                                  lineWidth: BSListeningTokens.hairline)
            }
        }
        .buttonStyle(BSListeningPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("listening.artistCandidate.\(candidate.id)")
    }
}
