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
}

@Model
final class TimetableStage {
    private(set) var id: UUID
    private(set) var name: String
    private(set) var sortOrder: Int
    var day: TimetableDay?

    @Relationship(deleteRule: .cascade, inverse: \TimetablePerformance.stage)
    private(set) var performances: [TimetablePerformance] = []

    init(
        id: UUID = UUID(), name: String, sortOrder: Int = 0,
        performances: [TimetablePerformance]
    ) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TimetableValidationError.emptyStageName }
        guard !performances.isEmpty else { throw TimetableValidationError.emptyStage }
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
}

@Model
final class TimetablePerformance {
    private(set) var id: UUID
    private(set) var artistName: String
    private(set) var startsAt: Date
    private(set) var endsAt: Date
    /// Explicit intent for this performance only; never inferred from listening or attendance.
    var isInterested: Bool = false
    var stage: TimetableStage?

    init(id: UUID = UUID(), artistName: String, startsAt: Date, endsAt: Date) throws {
        let artistName = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artistName.isEmpty else { throw TimetableValidationError.emptyArtistName }
        guard startsAt.timeIntervalSince1970.isFinite,
              endsAt.timeIntervalSince1970.isFinite, startsAt < endsAt else {
            throw TimetableValidationError.invalidPerformanceInterval
        }
        self.id = id
        self.artistName = artistName
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    static func chronologicalOrder(_ lhs: TimetablePerformance, _ rhs: TimetablePerformance) -> Bool {
        if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
        if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
