import Foundation

struct TimetableImportResult: Equatable, Sendable {
    var draft: TimetableDraft
    /// Sets without an artist or a start time; they have no place on the matrix.
    var skippedCount = 0
}

/// Maps an exchange document onto a reviewable draft. A set without a usable
/// end runs until the next set on its stage (or a default length); the user
/// corrects it on the matrix during review.
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
                var timed: [(artist: String, start: Int, end: Int?)] = []
                for performance in stage.performances {
                    let artist = performance.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard var start = minutes(from: performance.start), !artist.isEmpty else {
                        if !artist.isEmpty || performance.start != nil || performance.end != nil { skippedCount += 1 }
                        continue
                    }
                    if hasDaytimeSets, start < lateNightCutoffMinutes { start += 24 * 60 }
                    var end = minutes(from: performance.end)
                    if let endValue = end, endValue <= start {
                        let rolled = endValue + 24 * 60
                        end = endValue < 24 * 60 && rolled > start && rolled - start <= maxRolloverMinutes ? rolled : nil
                    }
                    timed.append((artist, start, end))
                }

                let starts = timed.map(\.start).sorted()
                var scheduled: [TimetableDraftPerformance] = []
                for set in timed {
                    let end = set.end ?? {
                        if let next = starts.first(where: { $0 > set.start }), next - set.start <= maxInferredSetMinutes {
                            return next
                        }
                        return set.start + defaultSetMinutes
                    }()
                    guard let startsAt = calendar.date(byAdding: .minute, value: set.start, to: date),
                          let endsAt = calendar.date(byAdding: .minute, value: end, to: date) else { continue }
                    let key = ArtistNameMatching.normalized(set.artist)
                    let isDuplicate = scheduled.contains {
                        ArtistNameMatching.normalized($0.artistName) == key && $0.startsAt == startsAt && $0.endsAt == endsAt
                    }
                    if !isDuplicate {
                        scheduled.append(TimetableDraftPerformance(artistName: set.artist, startsAt: startsAt, endsAt: endsAt))
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
