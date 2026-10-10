import CoreGraphics
import Foundation

/// Pure geometry for the stage matrix: time runs down, stages run across.
/// Overnight sets stay on the official day; the axis simply continues past 24:00.
struct TimetableMatrixLayout {
    struct Performance: Equatable {
        let id: UUID
        let artistName: String
        let startsAt: Date
        let endsAt: Date
        let isInterested: Bool
    }

    struct Stage: Equatable {
        let id: UUID
        let name: String
        let performances: [Performance]
    }

    enum Status: Equatable {
        case ended
        case live
        case soon(minutes: Int)
        case upcoming
    }

    enum Activity: Equatable { case idle, soon, live }

    struct Card: Identifiable, Equatable {
        let id: UUID
        let artistName: String
        let laneIndex: Int
        let top: CGFloat
        let height: CGFloat
        let startsAt: Date
        let endsAt: Date
        let status: Status
        let isInterested: Bool
    }

    struct Gap: Equatable {
        let laneIndex: Int
        let top: CGFloat
        let height: CGFloat
    }

    struct HourMark: Equatable {
        let y: CGFloat
        let date: Date
        let isMidnight: Bool
    }

    static let pointsPerMinute: CGFloat = 2.2
    static let topInset: CGFloat = 18
    static let bottomInset: CGFloat = 130
    static let cardSpacing: CGFloat = 3
    static let soonWindow: TimeInterval = 30 * 60
    static let changeoverThreshold: TimeInterval = 30 * 60

    let start: Date
    let end: Date
    /// Vertical scale; the share image uses a tighter one than the app.
    let pointsPerMinute: CGFloat
    let cards: [Card]
    let gaps: [Gap]
    let hours: [HourMark]
    let activity: [Activity]
    let nowY: CGFloat?

    var laneHeight: CGFloat { y(for: end) + 14 }
    var contentHeight: CGFloat { y(for: end) + Self.bottomInset }
    var midnightY: CGFloat? { hours.first(where: \.isMidnight)?.y }

    func y(for date: Date) -> CGFloat {
        Self.topInset + CGFloat(date.timeIntervalSince(start) / 60) * pointsPerMinute
    }

    func date(for y: CGFloat) -> Date {
        let minutes = max(0, (y - Self.topInset) / pointsPerMinute)
        return start.addingTimeInterval(Double(minutes) * 60)
    }

    init(stages: [Stage], now: Date, calendar: Calendar, pointsPerMinute: CGFloat = Self.pointsPerMinute) {
        let all = stages.flatMap(\.performances)
        let earliest = all.map(\.startsAt).min() ?? now
        let start = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        let end = all.map(\.endsAt).max() ?? start.addingTimeInterval(3600)
        self.start = start
        self.end = end
        self.pointsPerMinute = pointsPerMinute

        let ppm = pointsPerMinute
        func y(_ date: Date) -> CGFloat { Self.topInset + CGFloat(date.timeIntervalSince(start) / 60) * ppm }
        func status(_ p: Performance) -> Status {
            if p.endsAt <= now { return .ended }
            if p.startsAt <= now { return .live }
            let lead = p.startsAt.timeIntervalSince(now)
            return lead <= Self.soonWindow ? .soon(minutes: Int((lead / 60).rounded(.up))) : .upcoming
        }

        var cards: [Card] = []
        var gaps: [Gap] = []
        var activity: [Activity] = []
        for (lane, stage) in stages.enumerated() {
            let ordered = stage.performances.sorted { $0.startsAt < $1.startsAt }
            for p in ordered {
                cards.append(Card(
                    id: p.id, artistName: p.artistName, laneIndex: lane,
                    top: y(p.startsAt),
                    height: CGFloat(p.endsAt.timeIntervalSince(p.startsAt) / 60) * ppm - Self.cardSpacing,
                    startsAt: p.startsAt, endsAt: p.endsAt,
                    status: status(p), isInterested: p.isInterested
                ))
            }
            for (a, b) in zip(ordered, ordered.dropFirst()) where b.startsAt.timeIntervalSince(a.endsAt) >= Self.changeoverThreshold {
                gaps.append(Gap(laneIndex: lane, top: y(a.endsAt), height: y(b.startsAt) - y(a.endsAt) - Self.cardSpacing))
            }
            let states = ordered.map(status)
            activity.append(states.contains(.live) ? .live : states.contains { if case .soon = $0 { return true }; return false } ? .soon : .idle)
        }

        var hours: [HourMark] = []
        var mark = start
        while mark <= end {
            hours.append(HourMark(y: y(mark), date: mark, isMidnight: mark > start && calendar.component(.hour, from: mark) == 0))
            mark = mark.addingTimeInterval(3600)
        }

        self.cards = cards
        self.gaps = gaps
        self.hours = hours
        self.activity = activity
        self.nowY = (start...end).contains(now) ? y(now) : nil
    }
}
