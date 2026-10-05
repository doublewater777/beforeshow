import Foundation

struct TimetablePerformanceTiming: Equatable, Sendable {
    let id: UUID
    let stageID: UUID
    let startsAt: Date
    let endsAt: Date
}

struct TimetableDayTiming: Equatable, Sendable {
    let id: UUID
    let performances: [TimetablePerformanceTiming]

    var startsAt: Date? { performances.map(\.startsAt).min() }
    var endsAt: Date? { performances.map(\.endsAt).max() }
}

struct TimetableTimeFacts: Equatable, Sendable {
    let current: [TimetablePerformanceTiming]
    /// All future performances, chronologically ordered, including parallel starts.
    let upcoming: [TimetablePerformanceTiming]
    /// Remains present during breaks between performances on the same day.
    let activeDayID: UUID?
    let nextDayID: UUID?
    let lastEndedDayID: UUID?
    let finalEnd: Date?

    var hasEnded: Bool { finalEnd != nil && activeDayID == nil && nextDayID == nil }
}

enum TimetableTimePolicy {
    /// Half-open intervals [start, end): an adjacent set starts exactly when the
    /// previous one stops. Daily boundaries come from the actual imported schedule.
    static func facts(for days: [TimetableDayTiming], at now: Date) -> TimetableTimeFacts {
        let orderedDays = days.filter { !$0.performances.isEmpty }.sorted {
            if $0.startsAt != $1.startsAt { return $0.startsAt! < $1.startsAt! }
            return $0.id.uuidString < $1.id.uuidString
        }
        let performances = orderedDays.flatMap(\.performances).sorted(by: chronologicalOrder)
        return TimetableTimeFacts(
            current: performances.filter { $0.startsAt <= now && now < $0.endsAt },
            upcoming: performances.filter { now < $0.startsAt },
            activeDayID: orderedDays.first { $0.startsAt! <= now && now < $0.endsAt! }?.id,
            nextDayID: orderedDays.first { now < $0.startsAt! }?.id,
            lastEndedDayID: orderedDays.last { $0.endsAt! <= now }?.id,
            finalEnd: orderedDays.compactMap(\.endsAt).max()
        )
    }

    /// Same-stage and cross-stage overlaps use the same rule. Adjacency is not a conflict.
    static func overlaps(_ lhs: TimetablePerformanceTiming, _ rhs: TimetablePerformanceTiming) -> Bool {
        lhs.id != rhs.id && lhs.startsAt < rhs.endsAt && rhs.startsAt < lhs.endsAt
    }

    private static func chronologicalOrder(
        _ lhs: TimetablePerformanceTiming, _ rhs: TimetablePerformanceTiming
    ) -> Bool {
        if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
        if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
