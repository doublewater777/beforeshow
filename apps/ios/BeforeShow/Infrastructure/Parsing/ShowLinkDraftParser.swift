import Foundation

struct ShowLinkDraftParser {
    enum ParseError: Error, Equatable {
        case unsupportedSource
        case missingDate
    }

    var calendar: Calendar
    private var service: ShowLinkParsingService?

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.service = nil
    }

    init(service: ShowLinkParsingService, calendar: Calendar = .current) {
        self.calendar = calendar
        self.service = service
    }

    func draft(from urlString: String) async throws -> ShowDraft {
        // 与 UI 来源 chip / 云端 extractShowUrl 一致：无协议先补 https://
        let link = Self.normalizedLink(urlString)
        if let service {
            return try await service.parse(link: link)
        }

        return try localDraft(from: link)
    }

    func draft(from urlString: String) throws -> ShowDraft {
        try localDraft(from: Self.normalizedLink(urlString))
    }

    /// 粘贴无协议域名时补上 https://，避免 UI 已识别但提交 new URL 失败。
    static func normalizedLink(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains("://") { return trimmed }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        return "https://" + trimmed
    }

    /// URL query 里的单串艺名 → `[ArtistSlot]` 数组:先按换行,再按 `,，、` 拆,trim 后丢空。
    /// local parser 没有后端头像,所有 slot 的 avatarURL 留 `nil`。
    private static func splitLinkArtist(_ raw: String) -> [ArtistSlot] {
        let separators = CharacterSet(charactersIn: ",，、")
        let names = raw
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: separators) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.map { ArtistSlot(name: $0, avatarURL: nil) }
    }

    private func localDraft(from urlString: String) throws -> ShowDraft {
        guard let host = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))?.host()?.lowercased(),
              isSupportedHost(host) else {
            throw ParseError.unsupportedSource
        }

        let query = Dictionary(
            uniqueKeysWithValues: (URLComponents(string: urlString)?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        guard let dateString = query["date"],
              let date = parseDate(dateString) else {
            throw ParseError.missingDate
        }

        var draft = ShowDraft(
            name: query["name"] ?? "",
            date: date,
            city: query["city"] ?? "",
            venueName: query["venue"] ?? "",
            artists: Self.splitLinkArtist(query["artist"] ?? ""),
            source: .link
        )

        if let time = query["time"] {
            draft.startTime = parseTime(time, on: date)
        }
        if let endDate = query["endDate"] {
            draft.endDate = parseDate(endDate)
        }
        if let endTime = query["endTime"] {
            draft.endTime = parseTime(endTime, on: draft.endDate ?? date)
        }

        // 链接解析：日期必经 missingDate 校验，始终可计入「已识别」。
        var recognizedFields: Set<ShowDraftField> = [.date]
        if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.name)
        }
        if draft.startTime != nil {
            recognizedFields.insert(.startTime)
        }
        if !draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.city)
        }
        if !draft.venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.venueName)
        }
        if !draft.artists.isEmpty {
            recognizedFields.insert(.artist)
        }
        draft.recognizedFields = recognizedFields

        return draft
    }

    /// 仅匹配官方域名及其子域名，避免查询参数或 `notdamai.example` 之类误报。
    private func isSupportedHost(_ host: String) -> Bool {
        host == "damai.cn" || host.hasSuffix(".damai.cn")
            || host == "showstart.com" || host.hasSuffix(".showstart.com")
    }

    private func parseDate(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        guard let date = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ).date else { return nil }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        guard result.year == parts[0], result.month == parts[1], result.day == parts[2] else {
            return nil
        }
        return date
    }

    private func parseTime(_ string: String, on date: Date) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }
}
