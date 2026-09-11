import SwiftUI

// MARK: - Current Show Follow-up

struct CurrentShowFollowUpSummary: View {
    let shows: [Show]
    let formatter: ShowDisplayFormatter
    let now: Date
    var onOpenShowLibrary: () -> Void = {}
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(BSLocalization.text("之后还有"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.3)
                        .foregroundColor(BSColor.Stage.muted)
                    Text(BSLocalization.format("%lld 场", shows.count))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(BSColor.Stage.dim)
                }

                Spacer(minLength: 8)

                Button(action: onOpenShowLibrary) {
                    HStack(spacing: 3) {
                        Text(BSLocalization.text("全部现场"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("全部现场"))
            }

            ForEach(shows.prefix(2)) { show in
                NavigationLink {
                    ShowDetailView(show: show, onDetailVisibilityChange: onDetailVisibilityChange)
                } label: {
                    followUpRow(show)
                }
                .buttonStyle(.plain)
            }

            if shows.count > 2 {
                Button(action: onOpenShowLibrary) {
                    HStack(spacing: 8) {
                        Text(BSLocalization.format("查看全部现场 · %lld 场", shows.count))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .background(BSColor.Stage.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(BSColor.Stage.accent.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
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
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(summaryMeta(for: show))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(distanceText(to: show))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(BSColor.Stage.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
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
        let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: .current)
        let seconds = max(0, Int(start.timeIntervalSince(now)))
        if seconds >= 86_400 { return BSLocalization.format("%lld 天后", seconds / 86_400) }
        if seconds >= 3_600 { return BSLocalization.format("%lld 小时后", seconds / 3_600) }
        return BSLocalization.format("%lld 分钟后", max(1, seconds / 60))
    }
}

// MARK: - Current Show Library Entry Tile

struct CurrentShowLibraryEntryTile: View {
    let totalShowCount: Int
    let onOpenShowLibrary: () -> Void

    var body: some View {
        Button(action: onOpenShowLibrary) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 36, height: 36)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(BSLocalization.text("全部现场"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(BSLocalization.format("%lld 场现场", totalShowCount))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(BSColor.Stage.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.format("%@，%lld 场现场", BSLocalization.text("全部现场"), totalShowCount))
    }
}
