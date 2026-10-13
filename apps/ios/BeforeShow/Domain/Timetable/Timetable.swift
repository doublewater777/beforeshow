import Foundation
import SwiftData

enum TimetableValidationError: Error, Equatable {
    case invalidTimeZone
    case emptyTimetable
    case emptyDay
    case emptyStage
    case emptyStageName
    case emptyArtistName
    case invalidPerformanceInterval
    case invalidDayDate
    case duplicateIdentity
    case overlappingDays
    case alreadyOwned
}

/// Structured data and source images have separate lifetimes. ShowAsset continues
/// to own the original timetable images; deleting this graph does not delete them.
@Model
final class Timetable {
    private(set) var id: UUID
    private(set) var timeZoneIdentifier: String
    var show: Show?
    var needsDateConfirmation: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TimetableDay.timetable)
    private(set) var days: [TimetableDay] = []

    init(id: UUID = UUID(), timeZoneIdentifier: String, days: [TimetableDay]) throws {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw TimetableValidationError.invalidTimeZone
        }
        guard !days.isEmpty else { throw TimetableValidationError.emptyTimetable }
        guard days.allSatisfy({ $0.timetable == nil }) else {
            throw TimetableValidationError.alreadyOwned
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let ordered = days.sorted { $0.date < $1.date }
        let identities = days.map(\.id)
            + days.flatMap { $0.stages.map(\.id) }
            + days.flatMap { $0.stages.flatMap { $0.performances.map(\.id) } }
        guard Set(identities).count == identities.count else {
            throw TimetableValidationError.duplicateIdentity
        }
        var dates = Set<Date>()
        for day in ordered {
            // The official date identifies the service day, even when its final
            // performances run after midnight. Never group by the device's date.
            guard calendar.startOfDay(for: day.date) == day.date,
                  dates.insert(day.date).inserted,
                  let start = day.performances.map(\.startsAt).min(),
                  calendar.isDate(start, inSameDayAs: day.date) else {
                throw TimetableValidationError.invalidDayDate
            }
        }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            if let end = previous.performances.map(\.endsAt).max(),
               let start = next.performances.map(\.startsAt).min(), end > start {
                throw TimetableValidationError.overlappingDays
            }
        }
        self.id = id
        self.timeZoneIdentifier = timeZoneIdentifier
        self.days = days
    }

    var orderedDays: [TimetableDay] {
        days.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    }

    func matchesDates(of show: Show) -> Bool {
        let populated = orderedDays.filter { !$0.performances.isEmpty }
        guard !(show.changeStatus == .postponed && show.postponedDate == nil),
              let first = populated.first, let last = populated.last,
              calendar.isDate(first.date, inSameDayAs: show.effectiveDate) else { return false }
        let fields = show.declaredTimingFields
        guard let end = CurrentShowTimeState.effectiveEndDate(timing: fields, calendar: fields.eventCalendar(fallback: calendar)) else {
            return true
        }
        if calendar.isDate(last.date, inSameDayAs: end) {
            return true
        }
        // Overnight festival / show: the last service day (e.g. 10-15) runs past midnight into show.endDate (10-16).
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: last.date),
           calendar.isDate(nextDay, inSameDayAs: end) {
            if let lastEnd = last.performances.map(\.endsAt).max(),
               calendar.isDate(lastEnd, inSameDayAs: end) {
                return true
            }
            if show.endTime != nil {
                return true
            }
        }
        return false
    }

    @discardableResult
    func confirmDates(for show: Show) -> Bool {
        guard matchesDates(of: show) else { return false }
        needsDateConfirmation = false
        show.updatedAt = Date()
        return true
    }

    func updateDayDate(_ day: TimetableDay, to date: Date) throws {
        guard days.contains(where: { $0.id == day.id }) else { throw TimetableValidationError.alreadyOwned }
        let date = calendar.startOfDay(for: date)
        guard !days.contains(where: { $0.id != day.id && $0.date == date }) else {
            throw TimetableValidationError.invalidDayDate
        }
        let offset = calendar.dateComponents([.day], from: day.date, to: date).day ?? 0
        let shifted = try day.performances.map { performance in
            guard let start = calendar.date(byAdding: .day, value: offset, to: performance.startsAt),
                  let end = calendar.date(byAdding: .day, value: offset, to: performance.endsAt), start < end else {
                throw TimetableValidationError.invalidPerformanceInterval
            }
            return (performance, start, end)
        }
        if let start = shifted.map({ $0.1 }).min(), let end = shifted.map({ $0.2 }).max() {
            try validateDayInterval(date: date, start: start, end: end, excluding: day.id)
        }
        day.setDate(date)
        for (performance, start, end) in shifted {
            performance.startsAt = start
            performance.endsAt = end
        }
    }

    @discardableResult
    /// New days start with named, empty stages; sets are only added on purpose.
    func addDay(date: Date, stageNames: [String]) throws -> TimetableDay {
        let date = calendar.startOfDay(for: date)
        guard !days.contains(where: { $0.date == date }) else { throw TimetableValidationError.invalidDayDate }
        guard let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date) else {
            throw TimetableValidationError.invalidDayDate
        }
        let end = start.addingTimeInterval(45 * 60)
        try validateDayInterval(date: date, start: start, end: end)
        let stages = try stageNames.enumerated().map { index, name in
            try TimetableStage(name: name, sortOrder: index, performances: [], allowsEmpty: true)
        }
        let day = try TimetableDay(date: date, stages: stages)
        days.append(day)
        day.timetable = self
        return day
    }

    func removeDay(_ day: TimetableDay) throws {
        guard days.contains(where: { $0.id == day.id }) else { throw TimetableValidationError.alreadyOwned }
        guard days.count > 1 else { throw TimetableValidationError.emptyTimetable }
        days.removeAll { $0.id == day.id }
        day.timetable = nil
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    private func validateDayInterval(date: Date, start: Date, end: Date, excluding id: UUID? = nil) throws {
        guard calendar.isDate(start, inSameDayAs: date) else { throw TimetableValidationError.invalidDayDate }
        for other in days where other.id != id {
            if other.date < date, let otherEnd = other.performances.map(\.endsAt).max(), otherEnd > start {
                throw TimetableValidationError.overlappingDays
            }
            if other.date > date, let otherStart = other.performances.map(\.startsAt).min(), end > otherStart {
                throw TimetableValidationError.overlappingDays
            }
        }
    }

    /// Value-only input to the time policy; no persistence or UI dependencies escape.
    var timing: [TimetableDayTiming] {
        orderedDays.map { day in
            TimetableDayTiming(id: day.id, performances: day.stages.flatMap { stage in
                stage.performances.map {
                    TimetablePerformanceTiming(
                        id: $0.id, stageID: stage.id, startsAt: $0.startsAt, endsAt: $0.endsAt
                    )
                }
            })
        }
    }
}

@Model
final class TimetableDay {
    private(set) var id: UUID
    /// Midnight of the official performance date in Timetable.timeZoneIdentifier.
    private(set) var date: Date
    var timetable: Timetable?

    @Relationship(deleteRule: .cascade, inverse: \TimetableStage.day)
    private(set) var stages: [TimetableStage] = []

    init(id: UUID = UUID(), date: Date, stages: [TimetableStage]) throws {
        guard !stages.isEmpty else { throw TimetableValidationError.emptyDay }
        guard stages.allSatisfy({ $0.day == nil }) else { throw TimetableValidationError.alreadyOwned }
        guard Set(stages.map(\.id)).count == stages.count else {
            throw TimetableValidationError.duplicateIdentity
        }
        self.id = id
        self.date = date
        self.stages = stages
    }

    var orderedStages: [TimetableStage] {
        stages.sorted {
            $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder
        }
    }

    var performances: [TimetablePerformance] {
        stages.flatMap(\.performances).sorted(by: TimetablePerformance.chronologicalOrder)
    }

    fileprivate func setDate(_ date: Date) {
        self.date = date
    }

    @discardableResult
    func addStage(name: String) throws -> TimetableStage {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimetableValidationError.emptyStageName }
        let nextOrder = (stages.map(\.sortOrder).max() ?? -1) + 1
        let stage = try TimetableStage(name: trimmed, sortOrder: nextOrder, performances: [], allowsEmpty: true)
        stage.day = self
        self.stages.append(stage)
        return stage
    }

    /// Applies the order the user dragged stages into.
    func reorderStages(_ ids: [UUID]) {
        for stage in stages {
            if let index = ids.firstIndex(of: stage.id) { stage.sortOrder = index }
        }
    }

    func removeStage(_ stage: TimetableStage) throws {
        guard stages.count > 1 else { throw TimetableValidationError.emptyDay }
        stages.removeAll { $0.id == stage.id }
        stage.day = nil
    }
}

@Model
final class TimetableStage {
    private(set) var id: UUID
    var name: String
    var sortOrder: Int
    var day: TimetableDay?

    @Relationship(deleteRule: .cascade, inverse: \TimetablePerformance.stage)
    private(set) var performances: [TimetablePerformance] = []

    /// Imported stages must carry sets (review flags empty ones); stages the user
    /// creates by hand start empty via `allowsEmpty`.
    init(
        id: UUID = UUID(), name: String, sortOrder: Int = 0,
        performances: [TimetablePerformance], allowsEmpty: Bool = false
    ) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TimetableValidationError.emptyStageName }
        guard allowsEmpty || !performances.isEmpty else { throw TimetableValidationError.emptyStage }
        guard performances.allSatisfy({ $0.stage == nil }) else { throw TimetableValidationError.alreadyOwned }
        guard Set(performances.map(\.id)).count == performances.count else {
            throw TimetableValidationError.duplicateIdentity
        }
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.performances = performances
    }

    var orderedPerformances: [TimetablePerformance] {
        performances.sorted(by: TimetablePerformance.chronologicalOrder)
    }

    func updateName(_ newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimetableValidationError.emptyStageName }
        self.name = trimmed
    }
}

@Model
final class TimetablePerformance {
    private(set) var id: UUID
    var artistName: String
    var appleMusicArtistID: String?
    var artistAvatarURL: String?
    var startsAt: Date
    var endsAt: Date
    /// Explicit intent for this performance only; never inferred from listening or attendance.
    var isInterested: Bool = false
    var stage: TimetableStage?

    init(
        id: UUID = UUID(), artistName: String, startsAt: Date, endsAt: Date,
        appleMusicArtistID: String? = nil, artistAvatarURL: String? = nil
    ) throws {
        let artistName = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artistName.isEmpty else { throw TimetableValidationError.emptyArtistName }
        guard startsAt.timeIntervalSince1970.isFinite,
              endsAt.timeIntervalSince1970.isFinite, startsAt < endsAt else {
            throw TimetableValidationError.invalidPerformanceInterval
        }
        self.id = id
        self.artistName = artistName
        let artistID = appleMusicArtistID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasArtistID = artistID?.isEmpty == false
        self.appleMusicArtistID = hasArtistID ? artistID : nil
        self.artistAvatarURL = hasArtistID ? artistAvatarURL : nil
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    static func chronologicalOrder(_ lhs: TimetablePerformance, _ rhs: TimetablePerformance) -> Bool {
        if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
        if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func updateDetails(
        artistName: String,
        startsAt: Date,
        endsAt: Date,
        appleMusicArtistID: String? = nil,
        artistAvatarURL: String? = nil
    ) throws {
        let trimmed = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimetableValidationError.emptyArtistName }
        guard startsAt.timeIntervalSince1970.isFinite,
              endsAt.timeIntervalSince1970.isFinite, startsAt < endsAt else {
            throw TimetableValidationError.invalidPerformanceInterval
        }
        self.artistName = trimmed
        let artistID = appleMusicArtistID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasArtistID = artistID?.isEmpty == false
        self.appleMusicArtistID = hasArtistID ? artistID : nil
        self.artistAvatarURL = hasArtistID ? artistAvatarURL : nil
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    func shiftTimes(by interval: TimeInterval) {
        guard interval.isFinite && interval != 0 else { return }
        self.startsAt = self.startsAt.addingTimeInterval(interval)
        self.endsAt = self.endsAt.addingTimeInterval(interval)
    }

    func moveTo(stage targetStage: TimetableStage) {
        guard self.stage?.id != targetStage.id else { return }
        self.stage = targetStage
    }

    func connectArtist(_ artist: RecognizedArtist) {
        self.artistName = artist.canonicalName
        self.appleMusicArtistID = artist.id
        self.artistAvatarURL = artist.avatarURL?.absoluteString
    }

    func disconnectArtist() {
        self.appleMusicArtistID = nil
        self.artistAvatarURL = nil
    }
}
