import SwiftUI

struct ListeningDiscStatusBadge: View {
    let isPlaying: Bool

    var body: some View {
        Label(BSLocalization.text(isPlaying ? "正在播放中" : "已在播放机中"),
              systemImage: isPlaying ? "waveform" : "opticaldisc")
            .font(BSListeningTokens.badge)
            .foregroundStyle(BSColor.Stage.accent)
            .padding(.horizontal, BSSpacing.sm)
            .padding(.vertical, BSSpacing.xs)
            .background(BSColor.Stage.background.opacity(0.9), in: Capsule())
    }
}
