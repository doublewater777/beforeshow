import Foundation

enum ShowDraftSource: String, Equatable {
    case manual
    case screenshotOCR
    case link
}

enum ShowDraftField: String, Equatable, Hashable, CaseIterable {
    case name
    case date
    case startTime
    case city
    case venueName
    case artist
}

struct ShowDraft: Equatable {
    var name: String
    var date: Date
    var startTime: Date?
    var endDate: Date?
    var endTime: Date?
    var timeZoneSecondsFromGMT: Int?
    var endTimeZoneSecondsFromGMT: Int?
    var timeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var city: String
    var venueName: String
    var venueAddress: String
    /// 多个艺人槽位,每行带自己的头像 URL(`nil` 表示未识别)。
    var artists: [ArtistSlot] = []
    var coverImageURL: String
    var source: ShowDraftSource
    /// 识别导入成功写入的字段（仅 screenshotOCR / link 来源有意义，手动与编辑流为空）。
    var recognizedFields: Set<ShowDraftField>

    init(
        name: String = "",
        date: Date = Date(),
        startTime: Date? = nil,
        endDate: Date? = nil,
        endTime: Date? = nil,
        timeZoneSecondsFromGMT: Int? = nil,
        endTimeZoneSecondsFromGMT: Int? = nil,
        timeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        city: String = "",
        venueName: String = "",
        venueAddress: String = "",
        artists: [ArtistSlot] = [],
        coverImageURL: String = "",
        source: ShowDraftSource = .manual,
        recognizedFields: Set<ShowDraftField> = []
    ) {
        self.name = name
        self.date = date
        self.startTime = startTime
        self.endDate = endDate
        self.endTime = endTime
        self.timeZoneSecondsFromGMT = timeZoneSecondsFromGMT
        self.endTimeZoneSecondsFromGMT = endTimeZoneSecondsFromGMT
        self.timeZoneIdentifier = timeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
        self.city = city
        self.venueName = venueName
        self.venueAddress = venueAddress
        self.artists = Show.normalizedArtistSlots(artists)
        self.coverImageURL = coverImageURL
        self.source = source
        self.recognizedFields = recognizedFields
    }

    init(show: Show) {
        self.init(
            name: show.name,
            date: show.date,
            startTime: show.startTime,
            endDate: show.endDate,
            endTime: show.endTime,
            timeZoneSecondsFromGMT: show.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: show.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: show.timeZoneIdentifier,
            endTimeZoneIdentifier: show.endTimeZoneIdentifier,
            city: show.city ?? "",
            venueName: show.venueName ?? "",
            venueAddress: show.venueAddress ?? "",
            artists: show.artists,
            coverImageURL: show.coverImageURL ?? "",
            source: .manual
        )
    }

    func makeShow() throws -> Show {
        let prepared = try Show.prepared(from: self)
        return try Show(
            name: prepared.name,
            date: prepared.date,
            startTime: prepared.startTime,
            endDate: prepared.endDate,
            endTime: prepared.endTime,
            timeZoneSecondsFromGMT: prepared.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: prepared.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: prepared.timeZoneIdentifier,
            endTimeZoneIdentifier: prepared.endTimeZoneIdentifier,
            city: prepared.city,
            venueName: prepared.venueName,
            venueAddress: prepared.venueAddress,
            artists: prepared.artists,
            coverImageURL: prepared.coverImageURL
        )
    }

    func hasValidEndTime(calendar: Calendar = .current) -> Bool {
        guard let startTime else { return false }
        let eventCalendar = timingCalendar(fallback: calendar)
        return Show.hasValidEndTime(
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            calendar: eventCalendar,
            endCalendar: endTimingCalendar(fallback: calendar)
        )
    }

    func timingCalendar(fallback: Calendar = .current) -> Calendar {
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            var calendar = fallback
            calendar.timeZone = timeZone
            return calendar
        }
        guard let timeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: timeZoneSecondsFromGMT) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }

    func endTimingCalendar(fallback: Calendar = .current) -> Calendar {
        Show.timingCalendar(
            timeZoneIdentifier: endTimeZoneIdentifier ?? timeZoneIdentifier,
            timeZoneSecondsFromGMT: endTimeZoneSecondsFromGMT ?? timeZoneSecondsFromGMT,
            fallback: fallback
        )
    }

    func mergedTime(_ time: Date, into day: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: time)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
    }
}

extension ShowDraft {
    /// 把识别 / 链接解析的 `incoming` 草稿合并进 `self`,跳过用户已手改的字段。
    /// 首次 import（`userEdited` 为空）等价于旧的 `draft = incoming` 整段替换;
    /// 二次 import 时用户已手改的部分会被保护,避免 OCR / link 偷偷冲掉输入。
    /// `recognizedFields` 取并集后减去 `userEdited` —— 用户接管后「已识别」描边消失。
    mutating func mergeRespectingUserEdits(
        from incoming: ShowDraft,
        userEdited: Set<ShowDraftField>
    ) {
        if !userEdited.contains(.name), !incoming.name.isEmpty {
            name = incoming.name
        }
        if !userEdited.contains(.date) {
            date = incoming.date
        }
        if !userEdited.contains(.startTime) {
            startTime = incoming.startTime
        }
        if !userEdited.contains(.city), !incoming.city.isEmpty {
            city = incoming.city
        }
        if !userEdited.contains(.venueName), !incoming.venueName.isEmpty {
            venueName = incoming.venueName
        }
        if !userEdited.contains(.artist) {
            // OCR / link 没识别出艺人时保留本地已有艺人数组,只在识别出艺人时整段覆盖。
            if !incoming.artists.isEmpty {
                artists = incoming.artists
            }
        }
        // 时间字段不直接对应 ShowDraftField,跟着 startTime / date 走同样的开关。
        if !userEdited.contains(.startTime) {
            endDate = incoming.endDate
            endTime = incoming.endTime
            timeZoneSecondsFromGMT = incoming.timeZoneSecondsFromGMT
            endTimeZoneSecondsFromGMT = incoming.endTimeZoneSecondsFromGMT
            timeZoneIdentifier = incoming.timeZoneIdentifier
            endTimeZoneIdentifier = incoming.endTimeZoneIdentifier
        }
        venueAddress = incoming.venueAddress
        coverImageURL = incoming.coverImageURL
        if source == .manual { source = incoming.source }
        recognizedFields.formUnion(incoming.recognizedFields)
        recognizedFields.subtract(userEdited)
    }
}
