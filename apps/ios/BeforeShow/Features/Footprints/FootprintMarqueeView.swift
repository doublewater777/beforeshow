import SwiftUI

/// A venue marquee: chasing bulbs around a letter board with this week's status.
struct FootprintMarqueeView: View {
    let status: FootprintMarqueeStatus
    /// Room kept on the right of the board for the record that stands on it.
    var recordInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FootprintRoomPalette.bulbGlow.opacity(0.15)))
            bulbs
            board.padding(18)
        }
        .frame(height: recordInset > 0 ? 164 : 150)
        .shadow(color: .black.opacity(0.6), radius: 20, y: 18)
        .accessibilityElement(children: .combine)
    }

    private var board: some View {
        VStack(alignment: recordInset > 0 ? .leading : .center, spacing: 2) {
            Text(BSLocalization.text("NOW SHOWING"))
                .font(.system(size: 13, weight: .medium).width(.condensed))
                .tracking(5)
                .foregroundStyle(FootprintRoomPalette.marqueeInk.opacity(0.7))
            Text(BSLocalization.format(status.totalShows == 1 ? "%lld SHOW" : "%lld SHOWS", status.totalShows))
                .font(.system(size: 36, weight: .black).width(.compressed))
                .tracking(2)
                .foregroundStyle(FootprintRoomPalette.marqueeInk)
            Text(statusLine)
                .font(.system(size: 13, weight: .semibold).width(.condensed))
                .tracking(1)
                .lineLimit(recordInset > 0 ? 2 : 1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(FootprintRoomPalette.marqueeInk)
                .padding(.horizontal, recordInset > 0 ? 0 : 10)
        }
        .padding(.leading, recordInset > 0 ? 16 : 0)
        .padding(.trailing, recordInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: recordInset > 0 ? .leading : .center)
        .background {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(FootprintRoomPalette.marqueePaper)
                .overlay {
                    // Letter-board slats.
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if let days = status.daysSinceLast {
            parts.append(days == 0
                ? BSLocalization.text("上一场就在今天")
                : BSLocalization.format("上一场 %lld 天前", days))
        }
        if let month = status.nextMonth, let day = status.nextDay, let name = status.nextShowName {
            parts.append(BSLocalization.format("下一场 %@ %@", String(format: "%02d.%02d", month, day), name))
        }
        return parts.joined(separator: " · ")
    }

    private var bulbs: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { context in
            let phase = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.6) % 2
            Canvas { canvas, size in
                for (index, point) in Self.bulbPositions(in: size).enumerated() {
                    let lit = reduceMotion || index % 2 == phase
                    let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                    if lit {
                        canvas.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(FootprintRoomPalette.bulbGlow.opacity(0.25)))
                    }
                    canvas.fill(Path(ellipseIn: rect), with: .color(FootprintRoomPalette.bulb.opacity(lit ? 1 : 0.25)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func bulbPositions(in size: CGSize) -> [CGPoint] {
        let inset: CGFloat = 9, step: CGFloat = 17
        var points: [CGPoint] = []
        var x = inset
        while x <= size.width - inset { points.append(CGPoint(x: x, y: inset)); x += step }
        var y = inset + step
        while y <= size.height - inset { points.append(CGPoint(x: size.width - inset, y: y)); y += step }
        x = size.width - inset - step
        while x >= inset { points.append(CGPoint(x: x, y: size.height - inset)); x -= step }
        y = size.height - inset - step
        while y > inset { points.append(CGPoint(x: inset, y: y)); y -= step }
        return points
    }
}
