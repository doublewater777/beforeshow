import Foundation

enum LiveModePhase: Equatable, Sendable {
    /// Before any performance starts in the timetable.
    case upcoming(firstStartsAt: Date)
    /// Live on stage right now or during the active festival day.
    case active
    /// Today's sets have ended, but another festival day continues tomorrow.
    case dayEnded(nextDayStartsAt: Date?)
    /// The entire festival has finished its final set.
    case fullyEnded
}

struct LivePerformanceSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let artistName: String
    let stageID: UUID
    let stageName: String
    let startsAt: Date
    let endsAt: Date
    let isInterested: Bool
    let secondsUntilStart: TimeInterval
    let secondsUntilEnd: TimeInterval

    var isStartingSoon: Bool {
        secondsUntilStart > 0 && secondsUntilStart <= 1800
    }
}

struct LiveModeState: Equatable, Sendable {
    let phase: LiveModePhase
    let activeDayID: UUID?
    let currentPerformances: [LivePerformanceSnapshot]
    let upcomingPerformances: [LivePerformanceSnapshot]
    let hasAnyInterested: Bool

    var isLiveOnStage: Bool {
        phase == .active
    }
}

struct LivePerformanceInput: Equatable, Sendable {
    let id: UUID
    let artistName: String
    let stageID: UUID
    let stageName: String
    let startsAt: Date
    let endsAt: Date
    let isInterested: Bool
}

struct LiveDayInput: Equatable, Sendable {
    let id: UUID
    let date: Date
    let performances: [LivePerformanceInput]
}

/// Festival-day arithmetic for day-ended copy. A night that runs past midnight
/// still belongs to the day it started, so a festival day turns at 06:00.
enum FestivalDay {
    static let turnHour = 6

    /// Festival days from `from` to `to`: 0 = the same festival day, 1 = the next one.
    static func distance(from: Date, to: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: shifted(from))
        let end = calendar.startOfDay(for: shifted(to))
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// 「今天」「明天」or「10月14日」 for a day `distance` festival days out.
    static func word(for date: Date, distance: Int, calendar: Calendar) -> String {
        switch distance {
        case ...0: return BSLocalization.text("今天")
        case 1: return BSLocalization.text("明天")
        default:
            let parts = calendar.dateComponents([.month, .day], from: shifted(date))
            return BSLocalization.format("%d月%d日", parts.month ?? 1, parts.day ?? 1)
        }
    }

    /// The 06:00 turns in `(after, through]`, so timelines refresh the wording on time.
    static func turns(after start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var turns: [Date] = []
        var day = calendar.startOfDay(for: start)
        while let turn = calendar.date(bySettingHour: turnHour, minute: 0, second: 0, of: day), turn <= end {
            if turn > start { turns.append(turn) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return turns
    }

    private static func shifted(_ date: Date) -> Date {
        date.addingTimeInterval(-TimeInterval(turnHour * 3600))
    }
}

enum LiveModeStateEngine {
    /// How long before a later festival day's first set the state flips back to `.upcoming`.
    static let nextDayLead: TimeInterval = 4 * 3600

    /// Pure, deterministic function: (Timetable data, reference time) -> LiveModeState.
    /// Never infers location/walking ETA. Strictly uses actual scheduled times.
    static func calculate(
        days: [LiveDayInput],
        now: Date
    ) -> LiveModeState {
        let validDays = days.filter { !$0.performances.isEmpty }
            .sorted { $0.date < $1.date }

        guard !validDays.isEmpty else {
            return LiveModeState(
                phase: .fullyEnded,
                activeDayID: nil,
                currentPerformances: [],
                upcomingPerformances: [],
                hasAnyInterested: false
            )
        }

        let allPerformances = validDays.flatMap(\.performances)
        let hasAnyInterested = allPerformances.contains { $0.isInterested }

        guard let firstStart = allPerformances.map(\.startsAt).min(),
              let finalEnd = allPerformances.map(\.endsAt).max() else {
            return LiveModeState(
                phase: .fullyEnded,
                activeDayID: nil,
                currentPerformances: [],
                upcomingPerformances: [],
                hasAnyInterested: false
            )
        }

        // 1. Before festival starts
        if now < firstStart {
            let upcoming = selectUpcoming(from: allPerformances, now: now)
            return LiveModeState(
                phase: .upcoming(firstStartsAt: firstStart),
                activeDayID: validDays.first?.id,
                currentPerformances: [],
                upcomingPerformances: upcoming,
                hasAnyInterested: hasAnyInterested
            )
        }

        // 2. After final performance ends
        if now >= finalEnd {
            return LiveModeState(
                phase: .fullyEnded,
                activeDayID: nil,
                currentPerformances: [],
                upcomingPerformances: [],
                hasAnyInterested: hasAnyInterested
            )
        }

        // 3. Find current/active day
        // A day's active window spans from its earliest start to its latest end.
        let daySpans: [(day: LiveDayInput, start: Date, end: Date)] = validDays.compactMap { d in
            guard let s = d.performances.map(\.startsAt).min(),
                  let e = d.performances.map(\.endsAt).max() else { return nil }
            return (d, s, e)
        }

        // Check if currently inside one day's performance window
        if let currentSpan = daySpans.first(where: { now >= $0.start && now < $0.end }) {
            let dayPerfs = currentSpan.day.performances
            let current = selectCurrent(from: dayPerfs, now: now)
            let upcoming = selectUpcoming(from: dayPerfs, now: now)

            return LiveModeState(
                phase: .active,
                activeDayID: currentSpan.day.id,
                currentPerformances: current,
                upcomingPerformances: upcoming,
                hasAnyInterested: hasAnyInterested
            )
        }

        // Check if between days (multi-day intermission after today's sets ended)
        if let lastEndedIndex = daySpans.lastIndex(where: { now >= $0.end }) {
            let nextIndex = lastEndedIndex + 1
            if nextIndex < daySpans.count {
                let nextSpan = daySpans[nextIndex]
                let upcoming = selectUpcoming(from: nextSpan.day.performances, now: now)
                let leadToNext = nextSpan.start.timeIntervalSince(now)

                // If within 4 hours of next festival day starting, transition to upcoming so activity can restart!
                if leadToNext <= Self.nextDayLead && leadToNext > 0 {
                    return LiveModeState(
                        phase: .upcoming(firstStartsAt: nextSpan.start),
                        activeDayID: nextSpan.day.id,
                        currentPerformances: [],
                        upcomingPerformances: upcoming,
                        hasAnyInterested: hasAnyInterested
                    )
                }

                return LiveModeState(
                    phase: .dayEnded(nextDayStartsAt: nextSpan.start),
                    activeDayID: nil,
                    currentPerformances: [],
                    upcomingPerformances: upcoming,
                    hasAnyInterested: hasAnyInterested
                )
            } else {
                return LiveModeState(
                    phase: .fullyEnded,
                    activeDayID: nil,
                    currentPerformances: [],
                    upcomingPerformances: [],
                    hasAnyInterested: hasAnyInterested
                )
            }
        }

        // Fallback for before day 1 within spans
        let upcoming = selectUpcoming(from: allPerformances, now: now)
        return LiveModeState(
            phase: .upcoming(firstStartsAt: firstStart),
            activeDayID: validDays.first?.id,
            currentPerformances: [],
            upcomingPerformances: upcoming,
            hasAnyInterested: hasAnyInterested
        )
    }

    // MARK: - Current & Upcoming Sorting Policies

    /// Selects and orders currently active performances.
    /// Canonical Rule: Interested takes precedence; without interested, show objective
    /// parallel list without guessing user's location.
    private static func selectCurrent(
        from performances: [LivePerformanceInput],
        now: Date
    ) -> [LivePerformanceSnapshot] {
        let active = performances.filter { $0.startsAt <= now && now < $0.endsAt }

        let snapshots = active.map { makeSnapshot($0, now: now) }

        return snapshots.sorted { lhs, rhs in
            // 1. Interested takes precedence
            if lhs.isInterested != rhs.isInterested {
                return lhs.isInterested && !rhs.isInterested
            }
            // 2. Earlier start time
            if lhs.startsAt != rhs.startsAt {
                return lhs.startsAt < rhs.startsAt
            }
            // 3. Stage name deterministic ordering
            return lhs.stageName < rhs.stageName
        }
    }

    /// Selects upcoming performances chronologically.
    /// Prioritizes interested sets when available, while preserving timeline relevance.
    private static func selectUpcoming(
        from performances: [LivePerformanceInput],
        now: Date,
        limit: Int = 4
    ) -> [LivePerformanceSnapshot] {
        let future = performances.filter { $0.startsAt > now }
            .sorted { lhs, rhs in
                if lhs.startsAt != rhs.startsAt {
                    return lhs.startsAt < rhs.startsAt
                }
                if lhs.isInterested != rhs.isInterested {
                    return lhs.isInterested && !rhs.isInterested
                }
                return lhs.stageName < rhs.stageName
            }

        // If there are interested upcoming performances, guarantee they are surfaced
        let interested = future.filter(\.isInterested)
        let candidates: [LivePerformanceInput]

        if !interested.isEmpty {
            // Include interested sets plus immediate chronological sets
            var combined: [LivePerformanceInput] = []
            var seen = Set<UUID>()

            // Take the nearest upcoming interested set
            if let firstInterested = interested.first {
                combined.append(firstInterested)
                seen.insert(firstInterested.id)
            }

            // Fill with other chronological sets
            for item in future where !seen.contains(item.id) {
                combined.append(item)
                seen.insert(item.id)
                if combined.count >= limit { break }
            }
            candidates = combined.sorted { $0.startsAt < $1.startsAt }
        } else {
            candidates = Array(future.prefix(limit))
        }

        return candidates.map { makeSnapshot($0, now: now) }
    }

    private static func makeSnapshot(
        _ input: LivePerformanceInput,
        now: Date
    ) -> LivePerformanceSnapshot {
        LivePerformanceSnapshot(
            id: input.id,
            artistName: input.artistName,
            stageID: input.stageID,
            stageName: input.stageName,
            startsAt: input.startsAt,
            endsAt: input.endsAt,
            isInterested: input.isInterested,
            secondsUntilStart: input.startsAt.timeIntervalSince(now),
            secondsUntilEnd: input.endsAt.timeIntervalSince(now)
        )
    }
}
