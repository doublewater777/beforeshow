import SwiftUI

/// Pinned time ruler column on the leading edge of the timeline matrix.
/// - Fixed horizontally to the screen viewport during horizontal stage scrolling.
/// - Synchronized vertically with the stage timeline inside the vertical scroll content.
/// Only this thin wrapper follows the horizontal offset; the marks are skipped while scrolling.
struct TimetableMatrixRulerView: View {
    let layout: TimetableMatrixLayout
    let timeZone: TimeZone
    let now: Date
    let viewport: TimetableMatrixViewport

    var body: some View {
        let scrollOffsetX = viewport.scrollOffsetX
        let edge = min(1, scrollOffsetX / 20)
        TimetableMatrixRulerMarks(layout: layout, timeZone: timeZone, now: now)
            .equatable()
            .overlay(alignment: .trailing) {
                if scrollOffsetX > 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12 * edge))
                        .frame(width: 0.5)
                }
            }
            .overlay(alignment: .trailing) {
                TimetableMatrixEdgeShadow(opacity: scrollOffsetX > 1 ? 0.35 * edge : 0)
            }
            .contentShape(Rectangle())
            .offset(x: max(0, scrollOffsetX), y: 0)
    }
}

private struct TimetableMatrixRulerMarks: View, Equatable {
    let layout: TimetableMatrixLayout
    let timeZone: TimeZone
    let now: Date

    private static let ruler = TimetableStyle.matrixRulerWidth

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layout == rhs.layout && lhs.timeZone == rhs.timeZone && lhs.now == rhs.now
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimetableStyle.background
                .frame(width: Self.ruler, height: layout.contentHeight)

            // Time markings (aligned with the timeline grid hour lines)
            ForEach(layout.hours, id: \.date) { mark in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimetableTimeFormat.time(mark.date, timeZone: timeZone))
                        .font(TimetableStyle.mono(11))
                        .lineLimit(1)
                    if mark.isMidnight {
                        Image(systemName: "moon.fill")
                            .font(BSFont.V3.caption)
                    }
                }
                .foregroundStyle(mark.isMidnight ? TimetableStyle.night : TimetableStyle.muted)
                .frame(width: Self.ruler - 4, alignment: .trailing)
                .offset(x: 0, y: mark.y - 8)
            }

            // Current time badge on the ruler
            if let nowY = layout.nowY {
                let actualNowY = nowY - 9
                Text(TimetableTimeFormat.time(now, timeZone: timeZone))
                    .font(TimetableStyle.mono(10.5, weight: .bold))
                    .foregroundStyle(TimetableStyle.background)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TimetableStyle.now))
                    .shadow(color: TimetableStyle.now.opacity(0.6), radius: 4)
                    .offset(x: 2, y: actualNowY - 7)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.ruler, height: layout.contentHeight, alignment: .topLeading)
    }
}
