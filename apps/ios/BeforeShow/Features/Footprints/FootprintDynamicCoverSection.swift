import SwiftUI

// MARK: - Footprint preview

struct FootprintDynamicCoverSection: View {
    let show: Show
    let isPlaybackActive: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = false

    private var effectiveIsPlaying: Bool {
        isPlaying && isPlaybackActive && scenePhase == .active
    }

    var body: some View {
        if let cover = show.dynamicCover {
            VStack(alignment: .leading, spacing: BSSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    Text("动态封面")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Text(effectiveIsPlaying ? BSLocalization.text("播放中") : BSLocalization.text("已暂停"))
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.dim)
                }

                Button {
                    isPlaying.toggle()
                } label: {
                    ZStack {
                        DynamicCoverVideoPreviewView(
                            showID: show.id,
                            cover: cover,
                            isPlaying: effectiveIsPlaying
                        )
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.42)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        Image(systemName: effectiveIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(BSFont.heroTitle.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(effectiveIsPlaying ? BSLocalization.text("暂停动态封面") : BSLocalization.text("播放动态封面"))
            }
            .onDisappear { isPlaying = false }
        }
    }
}
