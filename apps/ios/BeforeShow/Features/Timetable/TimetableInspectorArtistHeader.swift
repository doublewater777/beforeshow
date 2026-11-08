import SwiftUI

/// The artist at the top of a set card: avatar and name open the shared artist page.
struct TimetableInspectorArtistHeader: View {
    let performance: TimetablePerformance
    let avatarURL: URL?
    let activeTrackTitle: String?

    private var reference: ArtistReference {
        ArtistReference(name: performance.artistName, appleMusicArtistID: performance.appleMusicArtistID, avatarURL: avatarURL)
    }

    var body: some View {
        NavigationLink {
            ArtistProfileView(reference: reference)
        } label: {
            HStack(spacing: 14) {
                TimetableArtistAvatar(name: performance.artistName, url: avatarURL, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(performance.artistName)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(TimetableStyle.foreground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TimetableStyle.dim)
                    }
                    status
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var status: some View {
        if let trackTitle = activeTrackTitle {
            Label(BSLocalization.format("正在试听 · %@", trackTitle), systemImage: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TimetableStyle.mine)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let id = performance.appleMusicArtistID, !id.isEmpty {
            Label(BSLocalization.text("已关联 Apple Music"), systemImage: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(TimetableStyle.mine)
        } else {
            Text(BSLocalization.text("未关联音乐库"))
                .font(.system(size: 12))
                .foregroundStyle(TimetableStyle.dim)
        }
    }
}
