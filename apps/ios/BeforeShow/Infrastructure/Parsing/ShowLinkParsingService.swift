import Foundation

/// 「如何获取链接」引导页里的单个平台：名称 + 总览页地址。
/// `isDomestic` 标记中国大陆购票平台，用于按语言环境排序。
struct ShowLinkGuidePlatform: Identifiable, Equatable {
    let id: String
    let displayName: String
    let overviewURL: String
    let isDomestic: Bool

    var url: URL? { URL(string: overviewURL) }
}

enum ShowLinkPlatformCatalog {
    private static let domainEntries: [(domain: String, displayName: String)] = [
        ("damai.cn", "大麦"),
        ("showstart.com", "秀动"),
        ("maoyan.com", "猫眼"),
        ("dpurl.cn", "猫眼"),
        ("piaoxingqiu.com", "票星球"),
        ("livelab.com.cn", "纷玩岛"),
        ("st.music.163.com", "网易云"),
        ("ticketmaster.com", "Ticketmaster"),
        ("ticketmaster.ca", "Ticketmaster"),
        ("ticketmaster.co.uk", "Ticketmaster"),
        ("ticketmaster.ie", "Ticketmaster"),
        ("ticketmaster.com.au", "Ticketmaster"),
        ("ticketmaster.co.nz", "Ticketmaster"),
        ("ticketmaster.com.mx", "Ticketmaster"),
        ("ticketmaster.at", "Ticketmaster"),
        ("ticketmaster.be", "Ticketmaster"),
        ("ticketmaster.com.br", "Ticketmaster"),
        ("ticketmaster.ch", "Ticketmaster"),
        ("ticketmaster.cl", "Ticketmaster"),
        ("ticketmaster.co", "Ticketmaster"),
        ("ticketmaster.cy", "Ticketmaster"),
        ("ticketmaster.cz", "Ticketmaster"),
        ("ticketmaster.de", "Ticketmaster"),
        ("ticketmaster.dk", "Ticketmaster"),
        ("ticketmaster.es", "Ticketmaster"),
        ("ticketmaster.fi", "Ticketmaster"),
        ("ticketmaster.fr", "Ticketmaster"),
        ("ticketmaster.gr", "Ticketmaster"),
        ("ticketmaster.it", "Ticketmaster"),
        ("ticketmaster.nl", "Ticketmaster"),
        ("ticketmaster.no", "Ticketmaster"),
        ("ticketmaster.pe", "Ticketmaster"),
        ("ticketmaster.ph", "Ticketmaster"),
        ("ticketmaster.pl", "Ticketmaster"),
        ("ticketmaster.se", "Ticketmaster"),
        ("ticketmaster.sg", "Ticketmaster"),
        ("ticketmaster.co.za", "Ticketmaster"),
        ("ticketmaster.ae", "Ticketmaster"),
        ("dice.fm", "DICE"),
        ("axs.com", "AXS"),
        ("livenation.com", "Live Nation"),
        ("livenation.asia", "Live Nation"),
        ("livenation.com.au", "Live Nation"),
        ("livenation.be", "Live Nation"),
        ("livenation.ca", "Live Nation"),
        ("livenation.cn", "Live Nation"),
        ("livenation.cz", "Live Nation"),
        ("livenation.dk", "Live Nation"),
        ("livenation.ee", "Live Nation"),
        ("livenation.fi", "Live Nation"),
        ("livenation.fr", "Live Nation"),
        ("livenation.de", "Live Nation"),
        ("livenation.hk", "Live Nation"),
        ("livenation.hu", "Live Nation"),
        ("livenation.co.il", "Live Nation"),
        ("livenation.it", "Live Nation"),
        ("livenation.co.jp", "Live Nation"),
        ("livenation.lt", "Live Nation"),
        ("livenation.nl", "Live Nation"),
        ("livenation.co.nz", "Live Nation"),
        ("livenation.no", "Live Nation"),
        ("livenation.pl", "Live Nation"),
        ("livenation.qa", "Live Nation"),
        ("livenation.sg", "Live Nation"),
        ("livenation.co.za", "Live Nation"),
        ("livenation.kr", "Live Nation"),
        ("livenation.es", "Live Nation"),
        ("livenation.se", "Live Nation"),
        ("livenation.com.tw", "Live Nation"),
        ("livenation.co.th", "Live Nation"),
        ("livenation.ae", "Live Nation"),
        ("livenation.co.uk", "Live Nation"),
        ("livenation.app.link", "Live Nation")
    ]

    static let supportSummary = "大麦、秀动、猫眼、票星球、纷玩岛、网易云、Ticketmaster、DICE、AXS、Live Nation"

    /// 「如何获取链接」引导页的平台总览入口；与网页版 link-guide 保持同一份数据。
    static let guidePlatforms: [ShowLinkGuidePlatform] = [
        ShowLinkGuidePlatform(id: "damai", displayName: "大麦", overviewURL: "https://m.damai.cn/shows/home.html", isDomestic: true),
        ShowLinkGuidePlatform(id: "showstart", displayName: "秀动", overviewURL: "https://showstart.com/", isDomestic: true),
        ShowLinkGuidePlatform(id: "maoyan", displayName: "猫眼", overviewURL: "https://show.maoyan.com/qqw/", isDomestic: true),
        ShowLinkGuidePlatform(id: "piaoxingqiu", displayName: "票星球", overviewURL: "https://e.piaoxingqiu.com/", isDomestic: true),
        ShowLinkGuidePlatform(id: "fenwandao", displayName: "纷玩岛", overviewURL: "https://www.livelab.com.cn/", isDomestic: true),
        ShowLinkGuidePlatform(id: "neteasemusic", displayName: "网易云", overviewURL: "https://st.music.163.com/g/show", isDomestic: true),
        ShowLinkGuidePlatform(id: "ticketmaster", displayName: "Ticketmaster", overviewURL: "https://www.ticketmaster.com/", isDomestic: false),
        ShowLinkGuidePlatform(id: "dice", displayName: "DICE", overviewURL: "https://dice.fm/", isDomestic: false),
        ShowLinkGuidePlatform(id: "axs", displayName: "AXS", overviewURL: "https://www.axs.com/", isDomestic: false),
        ShowLinkGuidePlatform(id: "livenation", displayName: "Live Nation", overviewURL: "https://www.livenation.com/", isDomestic: false)
    ]

    /// 引导页排序：中文环境国内平台在前，其他语言海外平台在前；组内保持声明顺序。
    static func guidePlatformsSorted(chineseFirst: Bool) -> [ShowLinkGuidePlatform] {
        let domestic = guidePlatforms.filter(\.isDomestic)
        let overseas = guidePlatforms.filter { !$0.isDomestic }
        return chineseFirst ? domestic + overseas : overseas + domestic
    }

    static func displayName(forHost host: String) -> String? {
        let normalizedHost = host.lowercased()
        return domainEntries.first { entry in
            normalizedHost == entry.domain || normalizedHost.hasSuffix(".\(entry.domain)")
        }?.displayName
    }
}

enum ShowLinkParsingError: Error, Equatable {
    case unsupportedSource
    case networkFailure
    case invalidResponse
    case notAShow
    case parseFailed(String)
}

protocol ShowLinkParsingService: Sendable {
    func parse(link: String) async throws -> ShowDraft
}

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

struct RemoteShowLinkParsingService: ShowLinkParsingService {
    var client: BeforeShowCloudClient
    var calendar: Calendar

    init(
        client: BeforeShowCloudClient,
        calendar: Calendar = .current
    ) {
        self.client = client
        self.calendar = calendar
    }

    func parse(link: String) async throws -> ShowDraft {
        let data: Data
        do {
            data = try await client.postJSON(
                path: "parseShowLink",
                body: RequestBody(
                    appInstanceId: client.credentials.appInstanceId,
                    appSignature: client.credentials.appSignature,
                    url: link
                )
            )
        } catch {
            throw ShowLinkParsingError.networkFailure
        }

        let decoded = try JSONDecoder().decode(ParseResponse.self, from: data)

        guard decoded.ok, let draft = decoded.draft else {
            if decoded.error?.code == "UNSUPPORTED_PLATFORM" {
                throw ShowLinkParsingError.unsupportedSource
            }
            if decoded.error?.code == "NOT_A_SHOW" {
                throw ShowLinkParsingError.notAShow
            }
            let message = decoded.error?.message ?? "Unknown error"
            throw ShowLinkParsingError.parseFailed(message)
        }

        return try mapDraft(draft)
    }

    private func mapDraft(_ draft: LinkParsedDraft) throws -> ShowDraft {
        let parsedStart = parseISODateTime(draft.startDateTime)
        let eventCalendar = calendar(
            identifier: draft.timeZoneIdentifier,
            offsetSeconds: parsedStart?.offsetSeconds
        )
        guard let date = parsedStart?.date ?? parseDate(draft.date, using: eventCalendar) else {
            throw ShowLinkParsingError.invalidResponse
        }

        let parsedEnd = parseISODateTime(draft.endDateTime)
        let endCalendar = calendar(
            identifier: draft.endTimeZoneIdentifier ?? draft.timeZoneIdentifier,
            offsetSeconds: parsedEnd?.offsetSeconds ?? parsedStart?.offsetSeconds
        )

        var showDraft = ShowDraft(
            name: draft.name,
            date: date,
            city: draft.city,
            venueName: draft.venueName,
            venueAddress: draft.venueAddr,
            artists: Self.splitLinkArtist(draft.artist, avatars: draft.artistAvatarURLs ?? []),
            coverImageURL: draft.coverImageURL ?? "",
            source: .link
        )

        if let parsedStart {
            showDraft.startTime = parsedStart.date
        } else if let startTime = draft.startTime, !startTime.isEmpty {
            guard let parsedStartTime = parseTime(startTime, on: date, using: eventCalendar) else {
                throw ShowLinkParsingError.invalidResponse
            }
            showDraft.startTime = parsedStartTime
        } else {
            showDraft.startTime = nil
        }
        if let parsedEnd {
            showDraft.endDate = parsedEnd.date
        } else if let endDate = draft.endDate, !endDate.isEmpty {
            guard let parsedEndDate = parseDate(endDate, using: endCalendar) else {
                throw ShowLinkParsingError.invalidResponse
            }
            showDraft.endDate = parsedEndDate
        }
        if let parsedEnd {
            showDraft.endTime = parsedEnd.date
        } else if let endTime = draft.endTime, !endTime.isEmpty {
            guard let parsedEndTime = parseTime(
                endTime,
                on: showDraft.endDate ?? date,
                using: endCalendar
            ) else {
                throw ShowLinkParsingError.invalidResponse
            }
            showDraft.endTime = parsedEndTime
        }
        showDraft.timeZoneSecondsFromGMT = parsedStart?.offsetSeconds
        showDraft.endTimeZoneSecondsFromGMT = parsedEnd?.offsetSeconds
        showDraft.timeZoneIdentifier = draft.timeZoneIdentifier
        showDraft.endTimeZoneIdentifier = draft.endTimeZoneIdentifier

        // 字段级 provenance：日期无效时已在上方抛 invalidResponse，始终可计入。
        var recognizedFields: Set<ShowDraftField> = [.date]
        if !showDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.name)
        }
        if showDraft.startTime != nil {
            recognizedFields.insert(.startTime)
        }
        if !showDraft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.city)
        }
        if !showDraft.venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.venueName)
        }
        if !showDraft.artists.isEmpty {
            recognizedFields.insert(.artist)
        }
        showDraft.recognizedFields = recognizedFields

        return showDraft
    }

    /// URL query 里的单串艺名 → `[ArtistSlot]` 数组:先按换行,再按 `,，、` 拆,trim 后丢空。
    /// 与后端返回的 `artistAvatarURLs` 按 index 对齐:多出的 slot 没头像置 `nil`,少则补空 slot。
    private static func splitLinkArtist(_ raw: String, avatars: [String] = []) -> [ArtistSlot] {
        let separators = CharacterSet(charactersIn: ",，、")
        let names = raw
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: separators) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.enumerated().map { index, name in
            let avatar = index < avatars.count ? avatars[index] : nil
            let cleaned = avatar?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ArtistSlot(name: name, avatarURL: (cleaned?.isEmpty ?? true) ? nil : cleaned)
        }
    }

    private func calendar(identifier: String?, offsetSeconds: Int?) -> Calendar {
        if let identifier,
           let timeZone = TimeZone(identifier: identifier) {
            var calendar = self.calendar
            calendar.timeZone = timeZone
            return calendar
        }
        if let offsetSeconds,
           let timeZone = TimeZone(secondsFromGMT: offsetSeconds) {
            var calendar = self.calendar
            calendar.timeZone = timeZone
            return calendar
        }
        return calendar
    }

    private func parseDate(_ string: String, using calendar: Calendar) -> Date? {
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

    private func parseTime(
        _ string: String,
        on date: Date,
        using calendar: Calendar
    ) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

    private func parseISODateTime(_ string: String?) -> (date: Date, offsetSeconds: Int?)? {
        guard let string, !string.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: string) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }() else {
            return nil
        }

        let offsetSeconds: Int?
        if string.hasSuffix("Z") {
            offsetSeconds = 0
        } else if let match = string.range(of: #"([+-])(\d{2}):(\d{2})$"#, options: .regularExpression) {
            let suffix = String(string[match])
            let sign = suffix.first == "-" ? -1 : 1
            let hour = Int(suffix.dropFirst().prefix(2)) ?? 0
            let minute = Int(suffix.dropFirst(4).prefix(2)) ?? 0
            offsetSeconds = sign * (hour * 3_600 + minute * 60)
        } else {
            offsetSeconds = nil
        }

        return (date, offsetSeconds)
    }
}

private struct RequestBody: Encodable {
    let appInstanceId: String
    let appSignature: String
    let url: String
}

private struct ParseResponse: Decodable {
    let ok: Bool
    let draft: LinkParsedDraft?
    let error: ParseErrorInfo?
}

private struct ParseErrorInfo: Decodable {
    let code: String
    let message: String
}

struct LinkParsedDraft: Decodable {
    let name: String
    let city: String
    let date: String
    let startTime: String?
    let startDateTime: String?
    let endDate: String?
    let endTime: String?
    let endDateTime: String?
    let timeZoneIdentifier: String?
    let endTimeZoneIdentifier: String?
    let venueName: String
    let venueAddr: String
    let artist: String
    let coverImageURL: String?
    let artistAvatarURLs: [String]?
    let priceRange: String
    let source: String
}
