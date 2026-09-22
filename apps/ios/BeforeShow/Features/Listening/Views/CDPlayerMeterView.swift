import SwiftUI

/// A playback activity meter, not an audio-frequency measurement.
struct CDPlayerMeterView: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isPlaying || reduceMotion)) { context in
            HStack(alignment: .bottom, spacing: CDPlayerSurfaceTokens.meterSpacing) {
                ForEach(CDPlayerSurfaceTokens.meterBaseHeights.indices, id: \.self) { index in
                    Rectangle().fill(CDPlayerSurfaceTokens.lcdGlow.opacity(isPlaying ? 1 : 0.4))
                        .frame(width: CDPlayerSurfaceTokens.meterWidth, height: height(index, at: context.date))
                }
            }
            .frame(height: CDPlayerSurfaceTokens.meterHeight, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func height(_ index: Int, at date: Date) -> CGFloat {
        guard isPlaying else { return CDPlayerSurfaceTokens.meterWidth }
        let full = CDPlayerSurfaceTokens.meterBaseHeights[index]
        guard !reduceMotion else { return full }
        let phase = date.timeIntervalSinceReferenceDate * 5.8 + Double(index) * 0.83
        return max(CDPlayerSurfaceTokens.meterWidth, full * (0.65 + 0.35 * sin(phase)))
    }
}
