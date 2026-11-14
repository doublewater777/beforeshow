import Foundation

/// Shared artist order for 看 and 本场歌单.
///
/// A `now` that lands on a show day lifts that whole day ahead of the others.
/// Before or after the run, nobody gets that lift: dated artists follow the
/// show calendar's day, then start time. The same start keeps lineup order,
/// and names that exist only on the timetable follow those. Lineup names with
/// no set stay last, in lineup order. One artist is one slot; a same-day set
/// wins over an earlier day when today is that show day.
enum ListeningLineupSchedule {
    struct Performance: Equatable {
        var name: String
        var day: Date
        var start: Date
        var timetableIndex: Int
    }

    struct Entry: Equatable {
        var name: String
        var performance: Performance?
    }

    static func ordered(
        lineup: [String],
        performances: [Performance],
        now: Date,
        calendar: Calendar
    ) -> [Entry] {
        var lineupIndex: [String: Int] = [:]
        var lineupNames: [String] = []
        for raw in lineup {
            let name = trimmed(raw)
            guard !name.isEmpty, lineupIndex[name] == nil else { continue }
            lineupIndex[name] = lineupNames.count
            lineupNames.append(name)
        }

        var grouped: [String: [Performance]] = [:]
        var timetableNames: [String] = []
        for raw in performances {
            let name = trimmed(raw.name)
            guard !name.isEmpty else { continue }
            if grouped[name] == nil { timetableNames.append(name) }
            grouped[name, default: []].append(Performance(
                name: name, day: raw.day, start: raw.start, timetableIndex: raw.timetableIndex
            ))
        }

        guard !grouped.isEmpty else {
            return lineupNames.map { Entry(name: $0, performance: nil) }
        }

        var names = lineupNames
        for name in timetableNames where lineupIndex[name] == nil {
            names.append(name)
        }

        let showDays = Set(grouped.values.flatMap { $0.map { calendar.startOfDay(for: $0.day) } })
        let today: Date? = showDays.contains(calendar.startOfDay(for: now)) ? now : nil
        let entries = names.map { name in
            Entry(name: name, performance: grouped[name].map { choose($0, today: today, calendar: calendar) })
        }
        let dated = entries.filter { $0.performance != nil }
        let undated = entries.filter { $0.performance == nil }
        let orderedDated: [Entry]
        if let today {
            let pinned = dated.filter { calendar.isDate($0.performance!.day, inSameDayAs: today) }
            let rest = dated.filter { !calendar.isDate($0.performance!.day, inSameDayAs: today) }
            orderedDated = pinned.sorted { startsBefore($0, $1) } + rest.sorted { scheduledBefore($0, $1, calendar) }
        } else {
            orderedDated = dated.sorted { scheduledBefore($0, $1, calendar) }
        }
        return orderedDated + undated
    }

    /// Moves today's programs in front of the other days. Relative order inside
    /// each side stays as given, so a day that is not today is not promoted.
    static func pinToday(
        _ programs: [(program: ListeningCompilationAssembler.LiveProgram, day: Date)],
        now: Date,
        calendar: Calendar
    ) -> [ListeningCompilationAssembler.LiveProgram] {
        guard programs.contains(where: { calendar.isDate(now, inSameDayAs: $0.day) }) else {
            return programs.map(\.program)
        }
        let pinned = programs.filter { calendar.isDate(now, inSameDayAs: $0.day) }
        let rest = programs.filter { !calendar.isDate(now, inSameDayAs: $0.day) }
        return (pinned + rest).map(\.program)
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func choose(_ performances: [Performance], today: Date?, calendar: Calendar) -> Performance {
        let pool: [Performance]
        if let today {
            let todays = performances.filter { calendar.isDate($0.day, inSameDayAs: today) }
            pool = todays.isEmpty ? performances : todays
        } else {
            pool = performances
        }
        return pool.min { lhs, rhs in
            let leftDay = calendar.startOfDay(for: lhs.day)
            let rightDay = calendar.startOfDay(for: rhs.day)
            if leftDay != rightDay { return leftDay < rightDay }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.timetableIndex < rhs.timetableIndex
        } ?? pool[0]
    }

    /// Equal starts are ties, so the stable sort keeps lineup order, then timetable order.
    private static func startsBefore(_ lhs: Entry, _ rhs: Entry) -> Bool {
        guard let left = lhs.performance, let right = rhs.performance, left.start != right.start else { return false }
        return left.start < right.start
    }

    private static func scheduledBefore(_ lhs: Entry, _ rhs: Entry, _ calendar: Calendar) -> Bool {
        guard let left = lhs.performance, let right = rhs.performance else { return false }
        let leftDay = calendar.startOfDay(for: left.day)
        let rightDay = calendar.startOfDay(for: right.day)
        if leftDay != rightDay { return leftDay < rightDay }
        if left.start != right.start { return left.start < right.start }
        return false
    }
}

@MainActor enum ListeningShowPlaylistOrdering {
    static func artistTracks(
        show: Show,
        browseArtists: [ListeningBrowseArtist],
        topTracks: (String) -> [ListeningDiscTrack],
        now: Date = Date()
    ) -> [[ListeningDiscTrack]] {
        var performances: [ListeningLineupSchedule.Performance] = []
        var index = 0
        for day in show.timetable?.orderedDays ?? [] {
            for stage in day.orderedStages {
                for set in stage.orderedPerformances {
                    performances.append(.init(
                        name: set.artistName, day: day.date, start: set.startsAt, timetableIndex: index
                    ))
                    index += 1
                }
            }
        }
        let ordered = ListeningLineupSchedule.ordered(
            lineup: show.artists.map(\.name),
            performances: performances,
            now: now,
            calendar: show.timingCalendar()
        )
        var tracksByName: [String: [ListeningDiscTrack]] = [:]
        for artist in browseArtists {
            let name = artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, tracksByName[name] == nil, let id = artist.appleMusicArtistID else { continue }
            tracksByName[name] = topTracks(id)
        }
        return ordered.compactMap { tracksByName[$0.name] }
    }
}
