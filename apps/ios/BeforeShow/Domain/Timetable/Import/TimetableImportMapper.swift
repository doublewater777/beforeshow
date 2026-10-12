import Foundation

struct TimetableImportResult: Equatable, Sendable {
    var draft: TimetableDraft
    /// Sets without an artist name; there is nothing to show for them.
    var skippedCount = 0
}

/// Maps an exchange document onto a reviewable draft. Missing or unusable
/// times are filled from neighbouring sets; the user corrects them on the
/// matrix during review.
enum TimetableImportMapper {
    static let maxDays = 31
    static let maxStagesPerDay = 30
    static let maxPerformances = 1500
    /// Starts before 06:00 belong to the previous evening when that day also has sets from noon on.
    static let lateNightCutoffMinutes = 6 * 60
    static let eveningMinutes = 12 * 60
    /// An end at or before its start means "after midnight" only for sets up to this long.
    static let maxRolloverMinutes = 6 * 60
    static let defaultSetMinutes = 45
    /// A missing end only borrows the next set's start when the gap is at most this long.
    static let maxInferredSetMinutes = 3 * 60
    /// Where a set with no time at all and nothing before it is placed.
    static let defaultStartMinutes = 18 * 60

    private typealias RawStage = (name: String, performances: [TimetableExchangeDocument.Performance])

    static func result(
        from document: TimetableExchangeDocument,
        defaultTimeZoneIdentifier: String,
        fallbackDate: Date,
        unnamedStage: (Int) -> String
    ) throws -> TimetableImportResult {
        let timeZoneIdentifier = try resolveTimeZone(document.timeZone, default: defaultTimeZoneIdentifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        let performanceCount = document.days.flatMap(\.stages).reduce(0) { $0 + $1.performances.count }
        guard document.days.count <= maxDays,
              document.days.allSatisfy({ $0.stages.count <= maxStagesPerDay }),
              performanceCount <= maxPerformances else {
            throw TimetableImportError.tooLarge
        }

        let grouped = try groupByDate(document, calendar: calendar, fallbackDate: fallbackDate, unnamedStage: unnamedStage)
        var days: [TimetableDraftDay] = []
        var skippedCount = 0

        for (date, stages) in grouped {
            let starts = stages.flatMap { $0.performances.compactMap { minutes(from: $0.start) } }
            let hasDaytimeSets = starts.contains { $0 >= eveningMinutes && $0 < 24 * 60 }
            var draftStages: [TimetableDraftStage] = []

            for stage in stages {
                var entries: [(artist: String, start: Int?, end: Int?)] = []
                for performance in stage.performances {
                    let artist = performance.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !artist.isEmpty else {
                        if performance.start != nil || performance.end != nil { skippedCount += 1 }
                        continue
                    }
                    var start = minutes(from: performance.start)
                    if let value = start, hasDaytimeSets, value < lateNightCutoffMinutes { start = value + 24 * 60 }
                    entries.append((artist, start, minutes(from: performance.end)))
                }

                // Missing times are filled from neighbouring sets so every set lands on
                // the matrix; the user corrects them there during review.
                let knownStarts = entries.compactMap(\.start).sorted()
                var scheduled: [TimetableDraftPerformance] = []
                var previousEnd: Int?
                for entry in entries {
                    let start: Int
                    if let known = entry.start {
                        start = known
                    } else if let previousEnd, entry.end == nil || rolledEnd(entry.end, after: previousEnd) != nil {
                        start = previousEnd
                    } else if let rawEnd = entry.end {
                        start = max(0, rawEnd - defaultSetMinutes)
                    } else {
                        start = defaultStartMinutes
                    }
                    let end = rolledEnd(entry.end, after: start) ?? {
                        if let next = knownStarts.first(where: { $0 > start }), next - start <= maxInferredSetMinutes {
                            return next
                        }
                        return start + defaultSetMinutes
                    }()
                    previousEnd = end
                    guard let startsAt = Self.date(minutes: start, on: date, calendar: calendar),
                          let endsAt = Self.date(minutes: end, on: date, calendar: calendar) else { continue }
                    let key = ArtistNameMatching.normalized(entry.artist)
                    let isDuplicate = scheduled.contains {
                        ArtistNameMatching.normalized($0.artistName) == key && $0.startsAt == startsAt && $0.endsAt == endsAt
                    }
                    if !isDuplicate {
                        scheduled.append(TimetableDraftPerformance(artistName: entry.artist, startsAt: startsAt, endsAt: endsAt))
                    }
                }
                if !scheduled.isEmpty {
                    draftStages.append(TimetableDraftStage(
                        name: stage.name,
                        sortOrder: draftStages.count,
                        performances: scheduled.sorted { $0.startsAt < $1.startsAt }
                    ))
                }
            }
            if !draftStages.isEmpty {
                days.append(TimetableDraftDay(date: date, stages: draftStages))
            }
        }

        guard !days.isEmpty else { throw TimetableImportError.noSchedule }
        let draft = TimetableDraft(timeZoneIdentifier: timeZoneIdentifier, days: days)
        do {
            _ = try draft.buildTimetable()
        } catch TimetableValidationError.overlappingDays {
            throw TimetableImportError.conflictingDays
        } catch TimetableValidationError.invalidDayDate {
            throw TimetableImportError.invalidDate
        } catch {
            throw TimetableImportError.invalidFormat
        }
        return TimetableImportResult(draft: draft, skippedCount: skippedCount)
    }

    /// An end at or before its start counts as after midnight only for a short set; otherwise it is unusable.
    private static func rolledEnd(_ raw: Int?, after start: Int) -> Int? {
        guard let raw else { return nil }
        if raw > start { return raw }
        let rolled = raw + 24 * 60
        return raw < 24 * 60 && rolled > start && rolled - start <= maxRolloverMinutes ? rolled : nil
    }

    /// Wall-clock time on the official day (minutes past 24:00 fall on the next
    /// calendar day), so daylight-saving changes never shift the printed time.
    private static func date(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        let minutesPerDay = 24 * 60
        guard let base = calendar.date(byAdding: .day, value: minutes / minutesPerDay, to: day) else { return nil }
        let clock = minutes % minutesPerDay
        return calendar.date(bySettingHour: clock / 60, minute: clock % 60, second: 0, of: base)
    }

    private static func resolveTimeZone(_ raw: String?, default identifier: String) throws -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return identifier
        }
        guard TimeZone(identifier: raw) != nil else { throw TimetableImportError.invalidTimeZone }
        return raw
    }

    /// Merges repeated dates and repeated stage names, keeping first-seen stage order.
    private static func groupByDate(
        _ document: TimetableExchangeDocument,
        calendar: Calendar,
        fallbackDate: Date,
        unnamedStage: (Int) -> String
    ) throws -> [(Date, [RawStage])] {
        let fallbackYear = calendar.component(.year, from: fallbackDate)
        var grouped: [Date: [RawStage]] = [:]
        for day in document.days {
            let date: Date
            if let raw = day.date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                guard let parsed = self.date(from: raw, fallbackYear: fallbackYear, calendar: calendar) else {
                    throw TimetableImportError.invalidDate
                }
                date = parsed
            } else {
                // A single-day schedule without a printed date is the show's own day.
                guard document.days.count == 1 else { throw TimetableImportError.missingDate }
                date = calendar.startOfDay(for: fallbackDate)
            }
            var stages = grouped[date] ?? []
            for (index, stage) in day.stages.enumerated() {
                var name = stage.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if name.isEmpty { name = unnamedStage(index + 1) }
                if let existing = stages.firstIndex(where: { $0.name == name }) {
                    stages[existing].performances += stage.performances
                } else {
                    stages.append((name, stage.performances))
                }
            }
            grouped[date] = stages
        }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// `YYYY-MM-DD`, or `MM-DD` when the year is not printed.
    static func date(from raw: String, fallbackYear: Int, calendar: Calendar) -> Date? {
        let parts = raw.split(whereSeparator: { "-/.".contains($0) }).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        let year: Int, month: Int, day: Int
        switch parts.count {
        case 3:
            guard parts[0].count == 4, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
            (year, month, day) = (y, m, d)
        case 2:
            guard let m = Int(parts[0]), let d = Int(parts[1]) else { return nil }
            (year, month, day) = (fallbackYear, m, d)
        default:
            return nil
        }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Minutes after the day's midnight for `HH:mm`; hours up to 29 express after-midnight sets.
    static func minutes(from raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "：" }).map(String.init)
        guard parts.count == 2, parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...29).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}
