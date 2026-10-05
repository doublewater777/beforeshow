import SwiftUI

struct HomeLiveTimetableSection: View {
    let state: LiveModeState
    var onOpenTimetable: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            // Header: Live status banner and Timetable entry button
            headerRow

            // Content based on phase
            switch state.phase {
            case .active:
                activeContent
            case .dayEnded(let nextStartsAt):
                dayEndedContent(nextStartsAt: nextStartsAt)
            case .upcoming(let firstStartsAt):
                upcomingContent(firstStartsAt: firstStartsAt)
            case .fullyEnded:
                fullyEndedContent
            }

            // Bottom action: Full timetable secondary entrance
            fullTimetableButton
        }
        .padding(BSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(BSColor.Stage.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [BSColor.Stage.accent.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.5)
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if state.phase == .active {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BSColor.Accent.prepare)
                        .frame(width: 8, height: 8)
                    Text(BSLocalization.text("现场模式"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BSColor.Stage.liveTitle)
                }
            } else if case .dayEnded = state.phase {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.Accent.warm)
                    Text(BSLocalization.text("今日已落幕"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BSColor.Accent.warm)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.textSecondary)
                    Text(BSLocalization.text("时刻表安排"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BSColor.textSecondary)
                }
            }

            Spacer()

            Button(action: onOpenTimetable) {
                HStack(spacing: 4) {
                    Text(BSLocalization.text("完整时刻表"))
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(BSColor.Accent.warm)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(BSColor.Accent.warm.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Currently on stage
            if !state.currentPerformances.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(BSLocalization.text("正在演出"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BSColor.Stage.dim)

                    ForEach(state.currentPerformances) { perf in
                        currentPerformanceRow(perf)
                    }
                }
            }

            // Up next
            if !state.upcomingPerformances.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(BSLocalization.text("接下来"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BSColor.Stage.dim)

                    ForEach(state.upcomingPerformances) { perf in
                        upcomingPerformanceRow(perf)
                    }
                }
            }
        }
    }

    private func currentPerformanceRow(_ perf: LivePerformanceSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(perf.stageName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.Accent.warm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BSColor.Accent.warm.opacity(0.12))
                        .clipShape(Capsule())

                    Text(formatTimeRange(start: perf.startsAt, end: perf.endsAt))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(BSColor.textSecondary)

                    if perf.isInterested {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.red)
                    }
                }

                Text(perf.artistName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(10)
        .background(BSColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(perf.isInterested ? Color.red.opacity(0.3) : BSColor.border, lineWidth: 1)
        )
    }

    private func upcomingPerformanceRow(_ perf: LivePerformanceSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formatTime(perf.startsAt))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(perf.isStartingSoon ? BSColor.Accent.warm : BSColor.textSecondary)

                    Text(perf.stageName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.textTertiary)

                    if perf.isStartingSoon {
                        startingSoonBadge(minutes: max(1, Int(perf.secondsUntilStart / 60)))
                    }

                    if perf.isInterested {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color.red)
                    }
                }

                Text(perf.artistName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(8)
        .background(perf.isStartingSoon ? BSColor.Accent.warm.opacity(0.06) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(perf.isStartingSoon ? BSColor.Accent.warm.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private func startingSoonBadge(minutes: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9))
            Text(BSLocalization.format("快开始了 (%d分)", minutes))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(BSColor.Accent.warm)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(BSColor.Accent.warm.opacity(0.18))
        .clipShape(Capsule())
    }

    private func dayEndedContent(nextStartsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BSLocalization.text("今日演出已全部落幕"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(BSColor.textPrimary)

            if let next = nextStartsAt {
                Text(BSLocalization.format("明日演出将于 %@ 继续开始", formatFullTime(next)))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
            } else {
                Text(BSLocalization.text("明日精彩继续，敬请期待"))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func upcomingContent(firstStartsAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BSLocalization.format("首场演出将于 %@ 开演", formatFullTime(firstStartsAt)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)

            if !state.upcomingPerformances.isEmpty {
                ForEach(state.upcomingPerformances.prefix(2)) { perf in
                    upcomingPerformanceRow(perf)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var fullyEndedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BSLocalization.text("本场音乐现场已全部谢幕"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)
            Text(BSLocalization.text("可回顾完整时刻表或记录现场足迹"))
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private var fullTimetableButton: some View {
        Button(action: onOpenTimetable) {
            HStack {
                Spacer()
                Text(BSLocalization.text("查看全部舞台完整排期"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(BSColor.Stage.dim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BSColor.Stage.dim)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        "\(formatTime(start)) - \(formatTime(end))"
    }

    private func formatFullTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
