import Foundation
import SwiftUI

struct FootprintTrendChart: View {
    let year: Int
    let months: [FootprintMonthActivity]
    let currentMonth: Int?
    let peakMonth: Int?

    var body: some View {
        GeometryReader { proxy in
           let width = proxy.size.width
           let chartHeight = proxy.size.height - 24
           let chartTop: CGFloat = 18
           let chartBottom = chartHeight - 8
           let plotHeight = max(1, chartBottom - chartTop)
           let visibleCount = max(1, min(currentMonth ?? months.count, months.count))
           let visibleMonths = Array(months.prefix(visibleCount))
           let maxCount = max(1, visibleMonths.map(\.showCount).max() ?? 1)
           let chartInset: CGFloat = 12
           let plotWidth = max(1, width - chartInset * 2)
           let points = months.enumerated().map { index, month in
               CGPoint(
                   x: chartInset + plotWidth * CGFloat(index) / CGFloat(max(months.count - 1, 1)),
                   y: chartBottom - plotHeight * CGFloat(month.showCount) / CGFloat(maxCount)
               )
           }
            let visiblePoints = Array(points.prefix(visibleCount))
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.075))
                        .frame(width: width, height: 1)
                        .position(x: width / 2, y: chartTop + CGFloat(index) * plotHeight / 2)
                }
                if let currentMonth, currentMonth >= 1, currentMonth <= months.count {
                    Path { path in
                        let point = points[currentMonth - 1]
                        path.move(to: CGPoint(x: point.x, y: chartTop))
                        path.addLine(to: CGPoint(x: point.x, y: chartBottom))
                    }
                    .stroke(BSColor.Stage.accent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                }
                if let first = visiblePoints.first {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: chartBottom))
                        path.addLine(to: first)
                        addSmoothSegments(to: &path, points: visiblePoints)
                        if let last = visiblePoints.last {
                            path.addLine(to: CGPoint(x: last.x, y: chartBottom))
                            path.closeSubpath()
                        }
                    }
                    .fill(LinearGradient(colors: [BSColor.Stage.accent.opacity(0.40), BSColor.Stage.accent.opacity(0.04)], startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.move(to: first)
                        addSmoothSegments(to: &path, points: visiblePoints)
                    }
                    .stroke(BSColor.Stage.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
               ForEach(Array(visiblePoints.enumerated()), id: \.offset) { index, point in
                   let month = months[index]
                   let isPeak = peakMonth == month.month
                   let isCurrent = currentMonth == month.month
                   Circle()
                       .fill(isCurrent ? BSColor.Stage.accent : BSColor.Stage.background)
                       .frame(width: isCurrent ? 10 : (isPeak ? 8 : 7), height: isCurrent ? 10 : (isPeak ? 8 : 7))
                       .overlay(Circle().stroke(BSColor.Stage.accent, lineWidth: isCurrent ? 3 : 2))
                       .shadow(color: BSColor.Stage.accent.opacity(isCurrent || isPeak ? 0.36 : 0.12), radius: isCurrent || isPeak ? 6 : 3)
                       .position(point)
               }
               ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                   Text(BSLocalization.text(footprintMonthKey(month.month)))
                       .font(.system(size: 8.5, weight: month.month == currentMonth ? .bold : .medium))
                       .foregroundColor(
                           month.month == currentMonth
                               ? BSColor.Stage.accent
                               : (currentMonth.map { month.month > $0 } ?? false ? BSColor.Stage.dim.opacity(0.68) : BSColor.Stage.foreground.opacity(0.65))
                       )
                       .position(x: points[index].x, y: proxy.size.height - 7)
               }
           }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BSLocalization.format("%lld 年 1 月到 12 月现场轨迹", year))
            .accessibilityValue(
                peakMonth
                    .flatMap { month in months.first(where: { $0.month == month }).map { BSLocalization.format("最高点 %lld 月，%lld 场", $0.month, $0.showCount) } }
                    ?? BSLocalization.text("暂无现场记录")
            )
        }
    }

    private func addSmoothSegments(to path: inout Path, points: [CGPoint]) {
        guard points.count > 1 else { return }
        for (start, end) in zip(points, points.dropFirst()) {
            let midpoint = (start.x + end.x) / 2
            path.addCurve(
                to: end,
                control1: CGPoint(x: midpoint, y: start.y),
                control2: CGPoint(x: midpoint, y: end.y)
            )
        }
    }
}

struct FootprintYearArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    @State private var selectedYear: Int

    init(
        archive: FootprintArchiveSnapshot,
        covers: [UUID: FootprintCover],
        onDetailVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.archive = archive
        self.covers = covers
        self.onDetailVisibilityChange = onDetailVisibilityChange
        _selectedYear = State(initialValue: archive.years.first?.year ?? Calendar.current.component(.year, from: Date()))
    }

    private var selectedGroup: FootprintYearGroup? {
        archive.years.first(where: { $0.year == selectedYear })
    }

    private var selectedActivity: FootprintYearActivity? {
        archive.yearActivity(for: selectedYear)
    }

    private var selectedSummary: FootprintYearArchiveSummary? {
        archive.yearArchiveSummary(for: selectedYear)
    }

    var body: some View {
        FootprintArchivePage(title: BSLocalization.text("年度档案"), kicker: "", shareCovers: covers) { isForExport in
            if let summary = selectedSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.year)")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundColor(BSColor.Stage.foreground)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(BSLocalization.format("%lld 场现场", summary.showCount))
                        Text("·")
                            .foregroundColor(BSColor.Stage.dim)
                        Text(ShowDurationFormatter.aggregate(totalMinutes: summary.durationMinutes))
                    }
                    .font(.system(size: 13))
                        .foregroundColor(BSColor.Stage.muted)
                }

                yearPicker(isForExport: isForExport)

                if let activity = selectedActivity {
                    yearRhythmCard(activity)
                }

                if let highlight = highlightShow {
                    yearHighlight(highlight, isForExport: isForExport)
                }

                archiveSectionTitle(BSLocalization.text("全部现场"), BSLocalization.format("%lld 场", summary.showCount))
                let yearShows = selectedGroup?.shows ?? []
                let visibleYearShows = isForExport
                    ? FootprintExportContentPolicy.prefix(yearShows, limit: FootprintExportContentPolicy.yearShowLimit)
                    : yearShows
                ForEach(visibleYearShows) { show in
                    yearShowRow(show, isForExport: isForExport)
                }
                if isForExport {
                    footprintExportRemainingCaption(
                        total: yearShows.count,
                        limit: FootprintExportContentPolicy.yearShowLimit
                    )
                }
            } else {
                Text(BSLocalization.text("暂无本地数据"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.vertical, 30)
            }
        }
    }

    @ViewBuilder
    private func yearPicker(isForExport: Bool) -> some View {
        if !isForExport, archive.years.count > 1 {
            let pills = HStack(spacing: 8) {
                ForEach(archive.years.map(\.year), id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedYear = year
                        }
                    } label: {
                        Text(String(year))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(year == selectedYear ? BSColor.Stage.background : BSColor.Stage.dim)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(year == selectedYear ? BSColor.Stage.accent : Color.white.opacity(0.045), in: Capsule())
                            .overlay(Capsule().stroke(year == selectedYear ? BSColor.Stage.accent : BSColor.Stage.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(year == selectedYear ? .isSelected : [])
                }
            }
            ScrollView(.horizontal, showsIndicators: false) { pills }
        }
    }

    private func yearRhythmCard(_ activity: FootprintYearActivity) -> some View {
        let maxCount = max(1, activity.months.map(\.showCount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(BSLocalization.format("%@ · %@", BSLocalization.text("年度节拍"), String(activity.year)))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(yearPeakText(activity))
                .font(.system(size: 9))
                .foregroundColor(BSColor.Stage.muted)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(activity.months) { month in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(month.showCount == maxCount && month.showCount > 0 ? BSColor.Stage.accent : BSColor.Stage.accent.opacity(0.46))
                            .frame(height: max(4, CGFloat(month.showCount) / CGFloat(maxCount) * 82))
                       Text(monthLabel(month.month))
                           .font(.system(size: 8.5, weight: .medium))
                           .foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 104, alignment: .bottom)
        }
        .padding(16)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BSColor.Stage.border))
    }

    private func yearHighlight(_ show: Show, isForExport: Bool) -> some View {
        footprintExportAwareNavigationLink(isForExport: isForExport) {
            FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
        } label: {
            HStack(spacing: 12) {
                FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                    .frame(width: 82, height: 94)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(BSLocalization.text("THE NIGHT OF THE YEAR"))
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.25)
                        .foregroundColor(BSColor.Stage.accent)
                    Text(show.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text([footprintEnhancementFullDateText(show.effectiveDate, calendar: show.timingCalendar()), FootprintTextNormalizer.nonEmptyTrimmed(show.city)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundColor(BSColor.Stage.muted)
                }
                Spacer(minLength: 0)
                footprintRowChevron(isForExport: isForExport, size: 10)
            }
            .padding(12)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BSColor.Stage.border))
        }
    }

    private func yearShowRow(_ show: Show, isForExport: Bool) -> some View {
        footprintExportAwareNavigationLink(isForExport: isForExport) {
            FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(footprintEnhancementDayText(show.effectiveDate, calendar: show.timingCalendar()).suffix(2)))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(footprintEnhancementMonthAbbreviation(show.effectiveDate, calendar: show.timingCalendar()))
                        .font(.system(size: 8))
                        .foregroundColor(BSColor.Stage.muted)
                }
                .frame(width: 38)
                FootprintCoverView(show: show, cover: covers[show.id])
                    .frame(width: 76, height: 86)
                    .clipped()
                VStack(alignment: .leading, spacing: 5) {
                    Text(show.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text([show.city, show.venueName].compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0) }.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                footprintRowChevron(isForExport: isForExport, size: 9)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1) }
        }
    }

    private var highlightShow: Show? {
        archive.yearHighlightShow(for: selectedYear, covers: covers)
    }

    private func yearPeakText(_ activity: FootprintYearActivity) -> String {
        footprintYearPeakText(activity)
    }

    private func monthLabel(_ month: Int) -> String {
        guard Calendar.current.shortMonthSymbols.indices.contains(month - 1) else { return "—" }
        return Calendar.current.shortMonthSymbols[month - 1].uppercased()
    }
}

func footprintYearPeakText(_ activity: FootprintYearActivity) -> String {
    guard let peak = activity.months.max(by: { $0.showCount < $1.showCount }), peak.showCount > 0 else {
        return BSLocalization.text("这一年还没有现场记录")
    }
    return BSLocalization.format("%lld 月是这一年最密集的一个月", peak.month)
}
