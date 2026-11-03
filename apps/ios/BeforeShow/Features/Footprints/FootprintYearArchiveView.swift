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
                   Text(BSLocalization.text(key: footprintMonthKey(month.month)))
                       .font(.system(size: 8.5, weight: month.month == currentMonth ? .bold : .medium))
                       .foregroundStyle(
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
