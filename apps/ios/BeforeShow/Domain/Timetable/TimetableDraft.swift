import Foundation

struct TimetableDraftPerformance: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var artistName: String
    var startsAt: Date
    var endsAt: Date
    var isInterested: Bool

    init(
        id: UUID = UUID(),
        artistName: String,
        startsAt: Date,
        endsAt: Date,
        isInterested: Bool = false
    ) {
        self.id = id
        self.artistName = artistName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isInterested = isInterested
    }

    init(from performance: TimetablePerformance) {
        self.id = performance.id
        self.artistName = performance.artistName
        self.startsAt = performance.startsAt
        self.endsAt = performance.endsAt
        self.isInterested = performance.isInterested
    }

    func buildPerformance() throws -> TimetablePerformance {
        let performance = try TimetablePerformance(
            id: id,
            artistName: artistName,
            startsAt: startsAt,
            endsAt: endsAt
        )
        performance.isInterested = isInterested
        return performance
    }
}

struct TimetableDraftStage: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var performances: [TimetableDraftPerformance]

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        performances: [TimetableDraftPerformance] = []
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.performances = performances
    }

    init(from stage: TimetableStage) {
        self.id = stage.id
        self.name = stage.name
        self.sortOrder = stage.sortOrder
        self.performances = stage.orderedPerformances.map(TimetableDraftPerformance.init)
    }

    func buildStage() throws -> TimetableStage {
        let perfs = try performances.map { try $0.buildPerformance() }
        return try TimetableStage(
            id: id,
            name: name,
            sortOrder: sortOrder,
            performances: perfs
        )
    }
}

struct TimetableDraftDay: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var stages: [TimetableDraftStage]

    init(
        id: UUID = UUID(),
        date: Date,
        stages: [TimetableDraftStage] = []
    ) {
        self.id = id
        self.date = date
        self.stages = stages
    }

    init(from day: TimetableDay) {
        self.id = day.id
        self.date = day.date
        self.stages = day.orderedStages.map(TimetableDraftStage.init)
    }

    func buildDay() throws -> TimetableDay {
        let builtStages = try stages.map { try $0.buildStage() }
        return try TimetableDay(id: id, date: date, stages: builtStages)
    }
}

struct TimetableDraftSummary: Equatable, Sendable {
    let dayCount: Int
    let stageCount: Int
    let performanceCount: Int
    let dateRangeDescription: String

    init(
        dayCount: Int,
        stageCount: Int,
        performanceCount: Int,
        dateRangeDescription: String
    ) {
        self.dayCount = dayCount
        self.stageCount = stageCount
        self.performanceCount = performanceCount
        self.dateRangeDescription = dateRangeDescription
    }
}

struct TimetableDraft: Equatable, Sendable {
    var timeZoneIdentifier: String
    var days: [TimetableDraftDay]

    init(timeZoneIdentifier: String = "Asia/Shanghai", days: [TimetableDraftDay] = []) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.days = days
    }

    init(from timetable: Timetable) {
        self.timeZoneIdentifier = timetable.timeZoneIdentifier
        self.days = timetable.orderedDays.map(TimetableDraftDay.init)
    }

    var summary: TimetableDraftSummary {
        let dCount = days.count
        let allStages = days.flatMap(\.stages)
        let uniqueStageNames = Set(allStages.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let sCount = max(uniqueStageNames.count, allStages.isEmpty ? 0 : 1)
        let pCount = allStages.flatMap(\.performances).count

        let rangeDesc: String
        if days.isEmpty {
            rangeDesc = ""
        } else {
            let sortedDays = days.sorted(by: { $0.date < $1.date })
            var calendar = Calendar(identifier: .gregorian)
            if let tz = TimeZone(identifier: timeZoneIdentifier) {
                calendar.timeZone = tz
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MM.dd"
            let firstStr = formatter.string(from: sortedDays.first!.date)
            let lastStr = formatter.string(from: sortedDays.last!.date)
            if sortedDays.count == 1 || firstStr == lastStr {
                rangeDesc = firstStr
            } else {
                rangeDesc = "\(firstStr) - \(lastStr)"
            }
        }

        return TimetableDraftSummary(
            dayCount: dCount,
            stageCount: sCount,
            performanceCount: pCount,
            dateRangeDescription: rangeDesc
        )
    }

    func buildTimetable(id: UUID = UUID()) throws -> Timetable {
        let builtDays = try days.map { try $0.buildDay() }
        return try Timetable(id: id, timeZoneIdentifier: timeZoneIdentifier, days: builtDays)
    }

    mutating func updatePerformance(id: UUID, artistName: String, startsAt: Date, endsAt: Date) {
        for dIndex in days.indices {
            for sIndex in days[dIndex].stages.indices {
                if let pIndex = days[dIndex].stages[sIndex].performances.firstIndex(where: { $0.id == id }) {
                    days[dIndex].stages[sIndex].performances[pIndex].artistName = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    days[dIndex].stages[sIndex].performances[pIndex].startsAt = startsAt
                    days[dIndex].stages[sIndex].performances[pIndex].endsAt = endsAt
                    return
                }
            }
        }
    }

    mutating func updateStageName(stageID: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for dIndex in days.indices {
            if let sIndex = days[dIndex].stages.firstIndex(where: { $0.id == stageID }) {
                days[dIndex].stages[sIndex].name = trimmed
            }
        }
    }

    mutating func removePerformance(id: UUID) {
        for dIndex in days.indices {
            for sIndex in days[dIndex].stages.indices {
                days[dIndex].stages[sIndex].performances.removeAll { $0.id == id }
            }
            days[dIndex].stages.removeAll { $0.performances.isEmpty }
        }
        days.removeAll { $0.stages.isEmpty }
    }

    mutating func removeStage(id: UUID) {
        for dIndex in days.indices {
            days[dIndex].stages.removeAll { $0.id == id }
        }
        days.removeAll { $0.stages.isEmpty }
    }
}
