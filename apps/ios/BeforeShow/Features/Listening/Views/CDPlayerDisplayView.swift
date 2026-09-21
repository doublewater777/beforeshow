import SwiftUI

struct CDPlayerDisplayView: View {
    let room: ListeningRoomCoordinator
    var extensionHeight: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var player: CDMechanism { room.mechanism }
    private var rect: CGRect { player.configuration.geometry.lcd }
    private var hasTrack: Bool { player.hasDisc && room.track != nil }

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(hasTrack ? room.track?.title ?? "CD" : BSLocalization.text("无唱片"))
                    .font(CDPlayerSurfaceTokens.lcdTitle)
                    .foregroundStyle(hasTrack ? BSColor.Stage.foreground : BSColor.Stage.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(hasTrack ? room.track?.artistName ?? "" : BSLocalization.text("打开上盖，选择唱片"))
                    .font(CDPlayerSurfaceTokens.lcdArtist)
                    .foregroundStyle(BSColor.textSecondary)
                    .lineLimit(1)
                if hasTrack {
                    Text(String(format: dynamicTypeSize.isAccessibilitySize ? "%02d / %02d\n%@" : "%02d / %02d · %@", room.trackIndex + 1, player.disc?.tracks.count ?? 0, room.timeText))
                        .font(CDPlayerSurfaceTokens.lcdMetadata)
                        .monospacedDigit()
                        .foregroundStyle(CDPlayerSurfaceTokens.lcdGlow)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: BSSpacing.xs) {
                CDPlayerMeterView(isPlaying: player.motion.spinning && room.isPlaybackVisible)
                Text(room.deviceStatus.label)
                    .font(CDPlayerSurfaceTokens.statusFont)
                    .tracking(1)
                    .foregroundStyle(CDPlayerSurfaceTokens.lcdGlow.opacity(0.8))
                    .accessibilityIdentifier("listening.deviceStatus")
            }
        }
        .padding(.horizontal, BSSpacing.compact)
        .frame(width: rect.width, height: rect.height + extensionHeight)
        .background {
            RoundedRectangle(cornerRadius: BSRadius.sm)
                .fill(CDPlayerSurfaceTokens.glass.shadow(.inner(color: .black, radius: BSSpacing.xs, y: 3)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.sm)
                .strokeBorder(.white.opacity(0.06), lineWidth: BSListeningTokens.hairline)
        }
        .position(x: rect.midX, y: rect.midY + extensionHeight / 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("listening.lcd")
    }
}
