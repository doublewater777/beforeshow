import Foundation
import SwiftData

enum ShowValidationError: Error, Equatable {
    case emptyName
    case missingStartTime
    case invalidEndTime
}

struct ShowDisplayFormatter {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func dateText(for show: Show) -> String {
        let startDay = show.effectiveDate
        let startClock = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar)
        let endClock = CurrentShowTimeState.effectiveEndTime(
            for: show,
            calendar: calendar,
            effectiveDate: show.effectiveDate,
            effectiveStartTime: startClock
        )

        // Multi-day range without an explicit end clock: show day span + daily start.
        // (Not tied to event category — any show can span days.)
        if let endDay,
           calendar.startOfDay(for: endDay) > calendar.startOfDay(for: startDay),
           endClock == nil {
            let range = dayRangeText(from: startDay, to: endDay)
            return "\(range) · 每日 \(timeText(startClock))"
        }

        var text = dateText(startDay)
        text += " \(timeText(startClock))"

        if let endClock {
            text += " - \(shortDateTimeText(endClock, includeDateWhenSameDayAs: startDay))"
        } else if let endDay,
                  calendar.startOfDay(for: endDay) > calendar.startOfDay(for: startDay) {
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
    var startTime: Date
    var endDate: Date?
    var endTime: Date?
    var city: String?
    var venueName: String?
    var venueAddress: String?
    var artist: String?
    var seatSection: String?
    var coverImageURL: String?
    private var artistAvatarURLStorage: [String]?
    var createdAt: Date
    var updatedAt: Date
    var postponedDate: Date?

    private var changeStatusRawValue: String

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
        startTime: Date,
        endDate: Date? = nil,
        endTime: Date? = nil,
        city: String? = nil,
        venueName: String? = nil,
        venueAddress: String? = nil,
        artist: String? = nil,
        seatSection: String? = nil,
        coverImageURL: String? = nil,
        artistAvatarURLs: [String] = [],
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
        self.venueAddress = venueAddress
        self.artist = artist
        self.seatSection = seatSection
        self.coverImageURL = coverImageURL
        self.artistAvatarURLStorage = artistAvatarURLs
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

    /// Single draft → 现场 mutation seam (create uses `ShowDraft.makeShow`, edit uses this).
    ///
    /// Deletion test: removing this method re-scatters trim/validate/field mapping across
    /// home edit, detail edit, and debug seeder. Does not touch
    /// `changeStatus` / `postponedDate` — those stay on mark* paths.
    func apply(_ draft: ShowDraft) throws {
        let prepared = try Self.prepared(from: draft)
        name = prepared.name
        date = prepared.date
        startTime = prepared.startTime
        endDate = prepared.endDate
        endTime = prepared.endTime
        city = prepared.city
        venueName = prepared.venueName
        venueAddress = prepared.venueAddress
        artist = prepared.artist
        seatSection = prepared.seatSection
        coverImageURL = prepared.coverImageURL
        artistAvatarURLs = prepared.artistAvatarURLs
        touch()
    }

    /// Normalize + validate draft fields once for create and edit.
    static func prepared(from draft: ShowDraft) throws -> PreparedShowDraft {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ShowValidationError.emptyName
        }
        guard let startTime = draft.startTime else {
            throw ShowValidationError.missingStartTime
        }
        guard hasValidEndTime(
            date: draft.date,
            startTime: startTime,
            endDate: draft.endDate,
            endTime: draft.endTime
        ) else {
            throw ShowValidationError.invalidEndTime
        }

        return PreparedShowDraft(
            name: trimmedName,
            date: draft.date,
            startTime: startTime,
            endDate: draft.endDate,
            endTime: draft.endTime,
            city: trimmedOptional(draft.city),
            venueName: trimmedOptional(draft.venueName),
            venueAddress: trimmedOptional(draft.venueAddress),
            artist: trimmedOptional(draft.artist),
            seatSection: trimmedOptional(draft.seatSection),
            coverImageURL: trimmedOptional(draft.coverImageURL),
            artistAvatarURLs: draft.artistAvatarURLs
        )
    }

    private func touch() {
        updatedAt = Date()
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func hasValidEndTime(
        date: Date,
        startTime: Date,
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

/// Normalized draft fields ready to write onto a `Show` (create or edit).
struct PreparedShowDraft: Equatable {
    let name: String
    let date: Date
    let startTime: Date
    let endDate: Date?
    let endTime: Date?
    let city: String?
    let venueName: String?
    let venueAddress: String?
    let artist: String?
    let seatSection: String?
    let coverImageURL: String?
    let artistAvatarURLs: [String]
}
