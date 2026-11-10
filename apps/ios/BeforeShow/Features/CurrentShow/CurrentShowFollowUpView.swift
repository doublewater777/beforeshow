import SwiftUI

struct CurrentShowFollowUpSummary: View {
    let shows: [Show]
    let formatter: ShowDisplayFormatter
    let now: Date
    var onOpenShowLibrary: () -> Void = {}
    var onSetCurrent: (Show) -> Void = { _ in }
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    @State private var revealedShowID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(BSLocalization.text("还有"))
                        .font(BSFont.Editorial.caps(13))
                        .tracking(1.5)
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(BSLocalization.format("%lld 场", shows.count))
                        .font(BSFont.Editorial.serif(15))
                        .foregroundStyle(BSColor.Stage.muted)
                }

                Spacer(minLength: 8)

                Button(action: onOpenShowLibrary) {
                    HStack(spacing: 3) {
                        Text(BSLocalization.text("全部现场"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("全部现场"))
            }

            ForEach(shows.prefix(2)) { show in
                BSSwipeRevealActionRow(
                    isRevealed: revealedShowID == show.id,
                    actionTitle: BSLocalization.text("设为当前"),
                    actionIcon: "pin.fill",
                    tint: BSColor.Stage.accent,
                    onReveal: { isRevealed in
                        revealedShowID = isRevealed ? show.id : nil
                    },
                    onAction: {
                        revealedShowID = nil
                        onSetCurrent(show)
                    }
                ) {
                    HStack(spacing: 0) {
                        NavigationLink {
                            ShowDetailView(show: show, onDetailVisibilityChange: onDetailVisibilityChange)
                        } label: {
                            followUpRow(show)
                        }
                        .buttonStyle(.plain)

                        CurrentShowSetCurrentButton {
                            revealedShowID = nil
                            onSetCurrent(show)
                        }
                        .padding(.trailing, 11)
                    }
                }
            }

            if shows.count > 2 {
                Button(action: onOpenShowLibrary) {
                    HStack(spacing: 8) {
                        Text(BSLocalization.format("查看全部现场 · %lld 场", shows.count))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .bsGlassCard(cornerRadius: 24)
            }
        }
    }

    private func followUpRow(_ show: Show) -> some View {
        HStack(spacing: 11) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                cornerRadius: 10
            )
            .frame(width: 45, height: 60)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(show.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(summaryMeta(for: show))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(distanceText(to: show))
                .font(BSFont.Editorial.serif(15))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(show.name)，\(summaryMeta(for: show))，\(distanceText(to: show))")
    }

    private func summaryMeta(for show: Show) -> String {
        let date = formatter.dateText(for: show)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [date, city].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private func distanceText(to show: Show) -> String {
        if CurrentShowFollowUpPolicy.isLive(show, now: now) {
            return BSLocalization.text("正在进行")
        }
        let start = CurrentShowFollowUpPolicy.firstStart(for: show)
        let calendar = show.timingFields.eventCalendar(fallback: .current)
        return CountdownCopy.until(
            remainingSeconds: max(0, Int(start.timeIntervalSince(now))),
            dayDistance: ShowCountdownRule.calendarDays(from: now, to: start, calendar: calendar)
        )
    }
}

struct CurrentShowLibraryEntryTile: View {
    let totalShowCount: Int
    let onOpenShowLibrary: () -> Void

    var body: some View {
        Button(action: onOpenShowLibrary) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 17))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(BSLocalization.text("全部现场"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(BSLocalization.format("%lld 场现场", totalShowCount))
                        .font(.system(size: 12.5))
                        .foregroundStyle(BSColor.Stage.muted)
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bsGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.format("%@，%lld 场现场", BSLocalization.text("全部现场"), totalShowCount))
    }
}
