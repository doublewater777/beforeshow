import Foundation
import SwiftData

enum ShowType: String, CaseIterable, Codable, Equatable {
    case concert
    case livehouse
    case musicFestival
}

extension ShowType {
    var displayName: String {
        switch self {
        case .concert: return "演唱会"
        case .livehouse: return "Livehouse"
        case .musicFestival: return "音乐节"
        }
    }
}

enum ShowChangeStatus: String, CaseIterable, Codable, Equatable {
    case scheduled
    case postponed
    case canceled
}

enum ShowValidationError: Error, Equatable {
    case emptyName
    case invalidEndTime
}

struct ShowDisplayFormatter {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func dateText(for show: Show) -> String {
        let startDay = show.effectiveDate
        let startClock = show.startTime == nil
            ? nil
            : CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar)
        let endClock = CurrentShowTimeState.effectiveEndTime(
            for: show,
            calendar: calendar,
            effectiveDate: show.effectiveDate,
            effectiveStartTime: startClock
        )

        if show.type == .musicFestival, let endDay {
            let range = dayRangeText(from: startDay, to: endDay)
            if let startClock {
                return "\(range) · 每日 \(timeText(startClock))"
            }
            return range
        }

        var text = dateText(startDay)
        if let startClock {
            text += " \(timeText(startClock))"
        }

        if let endClock {
            text += " - \(shortDateTimeText(endClock, includeDateWhenSameDayAs: startDay))"
        } else if let endDay {
            text += " - \(shortDateText(endDay))"
        }

        return text
    }

    func statusText(for show: Show) -> String {
        CurrentShowTimeState(show: show, calendar: calendar).statusText
    }

    func countdownText(for show: Show) -> String {
        CurrentShowTimeState(show: show, calendar: calendar).countdownText
    }

    private func dayRangeText(from start: Date, to end: Date) -> String {
        let startComponents = calendar.dateComponents([.year, .month, .day], from: start)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: end)
        let year = startComponents.year ?? calendar.component(.year, from: start)
        let startMonth = startComponents.month ?? 1
        let startDay = startComponents.day ?? 1
        let endMonth = endComponents.month ?? 1
        let endDay = endComponents.day ?? 1

        if startMonth == endMonth {
            return "\(year)年\(startMonth)月\(startDay)日-\(endDay)日"
        }
        return "\(year)年\(startMonth)月\(startDay)日-\(endMonth)月\(endDay)日"
    }

    private func dateText(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    private func shortDateText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    private func shortDateTimeText(_ date: Date, includeDateWhenSameDayAs startDay: Date) -> String {
        if calendar.isDate(date, inSameDayAs: startDay) {
            return timeText(date)
        }
        return "\(shortDateText(date)) \(timeText(date))"
    }

    private func timeText(_ date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

@Model
final class Show {
    var id: UUID
    var name: String
    var date: Date
    var startTime: Date?
    var endDate: Date?
    var endTime: Date?
    var city: String?
    var venueName: String?
    var artist: String?
    var seatSection: String?
    var coverImageURL: String?
    private var artistAvatarURLStorage: [String]?
    var createdAt: Date
    var updatedAt: Date
    var postponedDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \ShowFragment.show)
    var fragments: [ShowFragment] = []

    private var typeRawValue: String
    private var changeStatusRawValue: String

    var type: ShowType {
        get { ShowType(rawValue: typeRawValue) ?? .concert }
        set {
            typeRawValue = newValue.rawValue
            touch()
        }
    }

    var changeStatus: ShowChangeStatus {
        get { ShowChangeStatus(rawValue: changeStatusRawValue) ?? .scheduled }
        set {
            changeStatusRawValue = newValue.rawValue
            touch()
        }
    }

    var artistAvatarURLs: [String] {
        get { artistAvatarURLStorage ?? [] }
        set {
            artistAvatarURLStorage = newValue
            touch()
        }
    }

    var effectiveDate: Date {
        postponedDate ?? date
    }

    init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        startTime: Date? = nil,
        endDate: Date? = nil,
        endTime: Date? = nil,
        city: String? = nil,
        venueName: String? = nil,
        artist: String? = nil,
        seatSection: String? = nil,
        coverImageURL: String? = nil,
        artistAvatarURLs: [String] = [],
        type: ShowType,
        changeStatus: ShowChangeStatus = .scheduled,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ShowValidationError.emptyName
        }
        guard Self.hasValidEndTime(
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime
        ) else {
            throw ShowValidationError.invalidEndTime
        }

        self.id = id
        self.name = trimmedName
        self.date = date
        self.startTime = startTime
        self.endDate = endDate
        self.endTime = endTime
        self.city = city
        self.venueName = venueName
        self.artist = artist
        self.seatSection = seatSection
        self.coverImageURL = coverImageURL
        self.artistAvatarURLStorage = artistAvatarURLs
        self.typeRawValue = type.rawValue
        self.changeStatusRawValue = changeStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func markPostponed(newDate: Date?) {
        postponedDate = newDate
        changeStatus = .postponed
        touch()
    }

    func markCanceled() {
        changeStatus = .canceled
        touch()
    }

    func markScheduled() {
        postponedDate = nil
        changeStatus = .scheduled
        touch()
    }

    private func touch() {
        updatedAt = Date()
    }

    static func hasValidEndTime(
        date: Date,
        startTime: Date?,
        endDate: Date?,
        endTime: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        if let endDate,
           calendar.startOfDay(for: endDate) < calendar.startOfDay(for: date) {
            return false
        }

        guard let endTime else {
            return true
        }

        let startDay = calendar.startOfDay(for: date)
        let endDay = calendar.startOfDay(for: endDate ?? date)
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endTime)
        guard let effectiveEnd = calendar.date(
            bySettingHour: endComponents.hour ?? 0,
            minute: endComponents.minute ?? 0,
            second: endComponents.second ?? 0,
            of: endDay
        ) else {
            return false
        }

        guard let startTime else {
            return effectiveEnd >= startDay
        }

        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
        guard let effectiveStart = calendar.date(
            bySettingHour: startComponents.hour ?? 0,
            minute: startComponents.minute ?? 0,
            second: startComponents.second ?? 0,
            of: startDay
        ) else {
            return false
        }

        if endDate == nil,
           effectiveEnd <= effectiveStart {
            return true
        }

        return effectiveEnd > effectiveStart
    }
}
