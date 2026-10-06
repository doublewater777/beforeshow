import SwiftUI
import UIKit

struct TimetablePerformanceCard: View {
    let performance: TimetablePerformance
    let stageName: String
    let isNow: Bool
    let hasListeningEvidence: Bool
    let clashes: [TimetableClashInfo]
    let onToggleInterested: () -> Void

    @State private var isPressingHeart = false

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            // Top row: Time range, Now badge, Stage badge, and Interested toggle
            HStack(alignment: .center, spacing: BSSpacing.sm) {
                // Time range with monospace figures
                Text(timeRangeText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(isNow ? BSColor.Accent.prepare : BSColor.textSecondary)

                if isNow {
                    nowBadge
                }

                if !stageName.isEmpty {
                    stageBadge
                }

                Spacer()

                // Listening badge if evidence exists (weak visual cue only)
                if hasListeningEvidence {
                    listeningBadge
                }

                // Interested heart button
                interestedButton
            }

            // Main row: Artist name (flexible multiline, never truncated)
            Text(performance.artistName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
                .padding(.vertical, 2)

            // Bottom section: Clash warning if interested and overlapping with another interested performance
            if performance.isInterested && !clashes.isEmpty {
                clashNoticeView
            }
        }
        .padding(BSSpacing.md)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var nowBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(BSColor.Accent.prepare)
                .frame(width: 6, height: 6)
            Text(BSLocalization.text("正在演"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSColor.Accent.prepare)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(BSColor.Accent.prepare.opacity(0.12))
        .clipShape(Capsule())
    }

    private var stageBadge: some View {
        Text(stageName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(BSColor.Accent.warm)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(BSColor.Accent.warm.opacity(0.12))
            .clipShape(Capsule())
    }

    private var listeningBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "headphones")
                .font(.system(size: 10, weight: .semibold))
            Text(BSLocalization.text("常听"))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(BSColor.Accent.info)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(BSColor.Accent.info.opacity(0.10))
        .clipShape(Capsule())
    }

    private var interestedButton: some View {
        Button {
            triggerFeedback()
            onToggleInterested()
        } label: {
            ZStack {
                Circle()
                    .fill(performance.isInterested ? Color.red.opacity(0.16) : Color.white.opacity(0.06))
                    .frame(width: 34, height: 34)

                Image(systemName: performance.isInterested ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(performance.isInterested ? Color.red : BSColor.textSecondary)
                    .scaleEffect(isPressingHeart ? 1.25 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(performance.isInterested ? BSLocalization.text("取消想看") : BSLocalization.text("想看"))
    }

    private var clashNoticeView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(clashes) { clash in
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.Accent.warm)

                    Text(BSLocalization.format(
                        "与「%@」时间重叠 (%@)",
                        clash.conflictingArtistName,
                        formatTimeRange(start: clash.conflictingStartsAt, end: clash.conflictingEndsAt)
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BSColor.Accent.warm)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Accent.warm.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
    }

    private var cardBackground: Color {
        if isNow {
            return BSColor.surfaceElevated
        } else if performance.isInterested {
            return BSColor.surface.opacity(0.95)
        } else {
            return BSColor.surface
        }
    }

    private var cardBorderColor: Color {
        if isNow {
            return BSColor.Accent.prepare.opacity(0.4)
        } else if performance.isInterested && !clashes.isEmpty {
            return BSColor.Accent.warm.opacity(0.35)
        } else if performance.isInterested {
            return Color.red.opacity(0.3)
        } else {
            return BSColor.border
        }
    }

    private var timeRangeText: String {
        formatTimeRange(start: performance.startsAt, end: performance.endsAt)
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func triggerFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            isPressingHeart = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isPressingHeart = false
            }
        }
    }
}
