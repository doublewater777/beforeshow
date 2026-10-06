import SwiftUI

struct TimetableStageMatrixView: View {
    let day: TimetableDay?
    let referenceNow: Date
    let timeZone: TimeZone
    let onToggleInterested: (TimetablePerformance) -> Void

    private let hourHeight: CGFloat = 100.0
    private let timeRulerWidth: CGFloat = 46.0

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    private var allPerformances: [TimetablePerformance] {
        day?.performances ?? []
    }

    private var stages: [TimetableStage] {
        day?.orderedStages ?? []
    }

    private var dayStart: Date {
        guard let earliest = allPerformances.map(\.startsAt).min() else {
            return referenceNow
        }
        let hour = calendar.component(.hour, from: earliest)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: earliest) ?? earliest
    }

    private var dayEnd: Date {
        guard let latest = allPerformances.map(\.endsAt).max() else {
            return referenceNow
        }
        let hour = calendar.component(.hour, from: latest)
        let min = calendar.component(.minute, from: latest)
        let endHour = min > 0 ? hour + 1 : hour
        return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: latest) ?? latest
    }

    private var totalHours: Int {
        let hours = calendar.dateComponents([.hour], from: dayStart, to: dayEnd).hour ?? 4
        return max(2, hours)
    }

    private var totalHeight: CGFloat {
        CGFloat(totalHours) * hourHeight
    }

    // Detected overlaps between interested performances
    private var interestedClashIntervals: [(start: Date, end: Date)] {
        let interested = allPerformances.filter(\.isInterested)
        guard interested.count > 1 else { return [] }

        var intervals: [(start: Date, end: Date)] = []
        for i in 0..<interested.count {
            for j in (i + 1)..<interested.count {
                let p1 = interested[i]
                let p2 = interested[j]
                guard p1.stage?.id != p2.stage?.id else { continue }
                let overlapStart = max(p1.startsAt, p2.startsAt)
                let overlapEnd = min(p1.endsAt, p2.endsAt)
                if overlapStart < overlapEnd {
                    intervals.append((start: overlapStart, end: overlapEnd))
                }
            }
        }
        return intervals
    }

    var body: some View {
        if stages.isEmpty || allPerformances.isEmpty {
            emptyMatrixView
        } else {
            GeometryReader { geo in
                let availableWidth = geo.size.width - timeRulerWidth - 12
                let columnWidth = stages.count <= 2
                    ? max(130, availableWidth / CGFloat(stages.count))
                    : max(145, availableWidth / 2.2)

                ScrollView(.vertical, showsIndicators: false) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Sticky stage headers
                            stageHeaderRow(columnWidth: columnWidth)
                                .padding(.leading, timeRulerWidth)
                                .padding(.bottom, 8)

                            // Matrix body: Time ruler on left + Grid columns on right
                            HStack(alignment: .top, spacing: 0) {
                                timeRulerColumn

                                ZStack(alignment: .topLeading) {
                                    // Background grid lines
                                    gridBackground(totalColumns: stages.count, columnWidth: columnWidth)

                                    // Amber bands for interested clashes
                                    ForEach(interestedClashIntervals.indices, id: \.self) { idx in
                                        let interval = interestedClashIntervals[idx]
                                        clashBand(interval: interval, totalWidth: columnWidth * CGFloat(stages.count))
                                    }

                                    // Columns with performances
                                    HStack(spacing: 8) {
                                        ForEach(stages, id: \.id) { stage in
                                            stageColumn(stage: stage, width: columnWidth)
                                        }
                                    }

                                    // Live current time indicator
                                    if shouldShowLiveLine {
                                        liveCurrentTimeLine(totalWidth: columnWidth * CGFloat(stages.count))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(minHeight: totalHeight + 80)
        }
    }

    // MARK: - Subviews

    private var emptyMatrixView: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundColor(BSColor.textTertiary)
            Text(BSLocalization.text("该日期下没有排期数据"))
                .font(.system(size: 14))
                .foregroundColor(BSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func stageHeaderRow(columnWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(stages, id: \.id) { stage in
                HStack(spacing: 5) {
                    Circle()
                        .fill(stageColor(for: stage.sortOrder))
                        .frame(width: 7, height: 7)
                    Text(stage.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)
                }
                .frame(width: columnWidth, height: 32)
                .background(BSColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var timeRulerColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<totalHours, id: \.self) { hourOffset in
                let hourDate = calendar.date(byAdding: .hour, value: hourOffset, to: dayStart) ?? dayStart
                Text(formatHour(hourDate))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(BSColor.textTertiary)
                    .frame(width: timeRulerWidth - 8, height: hourHeight, alignment: .topTrailing)
                    .padding(.top, -6)
            }
        }
        .frame(width: timeRulerWidth)
    }

    private func gridBackground(totalColumns: Int, columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Horizontal hour gridlines
            VStack(spacing: 0) {
                ForEach(0..<totalHours, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                        .frame(width: (columnWidth + 8) * CGFloat(totalColumns))
                        .padding(.bottom, hourHeight - 1)
                }
            }
        }
    }

    private func stageColumn(stage: TimetableStage, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: totalHeight)

            ForEach(stage.performances, id: \.id) { perf in
                let y = yOffset(for: perf.startsAt)
                let h = height(from: perf.startsAt, to: perf.endsAt)

                performanceBlock(perf: perf, stageOrder: stage.sortOrder)
                    .frame(width: width, height: h)
                    .offset(y: y)
            }
        }
        .frame(width: width, height: totalHeight)
    }

    private func performanceBlock(perf: TimetablePerformance, stageOrder: Int) -> some View {
        let isNow = TimetablePeriodPolicy.isNow(
            startsAt: perf.startsAt,
            endsAt: perf.endsAt,
            at: referenceNow
        )

        return Button {
            onToggleInterested(perf)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    if isNow {
                        Circle()
                            .fill(BSColor.Accent.prepare)
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                    }

                    Text(perf.artistName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if perf.isInterested {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.red)
                    }
                }

                Spacer(minLength: 0)

                Text(formatTimeRange(start: perf.startsAt, end: perf.endsAt))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isNow ? BSColor.Accent.prepare : BSColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(blockBackground(isNow: isNow, isInterested: perf.isInterested, stageOrder: stageOrder))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        perf.isInterested
                            ? Color.red.opacity(0.6)
                            : (isNow ? BSColor.Accent.prepare : Color.white.opacity(0.12)),
                        lineWidth: perf.isInterested || isNow ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func clashBand(interval: (start: Date, end: Date), totalWidth: CGFloat) -> some View {
        let y = yOffset(for: interval.start)
        let h = height(from: interval.start, to: interval.end)

        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.12),
                        Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .stroke(
                        Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .frame(width: totalWidth, height: max(16, h))
            .offset(y: y)
            .allowsHitTesting(false)
    }

    private var shouldShowLiveLine: Bool {
        referenceNow >= dayStart && referenceNow <= dayEnd
    }

    private func liveCurrentTimeLine(totalWidth: CGFloat) -> some View {
        let y = yOffset(for: referenceNow)

        return HStack(spacing: 0) {
            Circle()
                .fill(BSColor.Accent.prepare)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(BSColor.Accent.prepare)
                .frame(width: totalWidth, height: 1.5)
        }
        .offset(x: -3, y: y - 3.5)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func yOffset(for date: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(dayStart) / 60.0
        return CGFloat(minutes) * (hourHeight / 60.0)
    }

    private func height(from start: Date, to end: Date) -> CGFloat {
        let durationMinutes = max(15.0, end.timeIntervalSince(start) / 60.0)
        return CGFloat(durationMinutes) * (hourHeight / 60.0)
    }

    private func stageColor(for order: Int) -> Color {
        switch order % 3 {
        case 0: return Color(red: 0.35, green: 0.65, blue: 1.0) // Strawberry blue
        case 1: return Color(red: 1.0, green: 0.45, blue: 0.6)  // Love pink
        default: return BSColor.Accent.warm
        }
    }

    private func blockBackground(isNow: Bool, isInterested: Bool, stageOrder: Int) -> Color {
        if isNow {
            return BSColor.surfaceElevated
        } else if isInterested {
            return Color(red: 0.14, green: 0.08, blue: 0.10)
        } else {
            return BSColor.surface.opacity(0.9)
        }
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}
