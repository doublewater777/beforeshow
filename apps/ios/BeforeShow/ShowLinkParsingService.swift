import Foundation

enum ShowLinkPlatformCatalog {
    private static let domainEntries: [(domain: String, displayName: String)] = [
        ("damai.cn", "大麦"),
        ("showstart.com", "秀动"),
        ("maoyan.com", "猫眼"),
        ("piaoxingqiu.com", "票星球"),
        ("livelab.com.cn", "纷玩岛"),
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

    static let supportSummary = "大麦、秀动、猫眼、票星球、纷玩岛、Ticketmaster、DICE、AXS、Live Nation"

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
            let message = decoded.error?.message ?? "Unknown error"
            throw ShowLinkParsingError.parseFailed(message)
        }

        return try mapDraft(draft)
    }

    private func mapDraft(_ draft: LinkParsedDraft) throws -> ShowDraft {
        guard let date = parseDate(draft.date) else {
            throw ShowLinkParsingError.invalidResponse
        }

        var showDraft = ShowDraft(
            name: draft.name,
            date: date,
            city: draft.city,
            venueName: draft.venueName,
            venueAddress: draft.venueAddr,
            artist: draft.artist,
            coverImageURL: draft.coverImageURL ?? "",
            artistAvatarURLs: draft.artistAvatarURLs ?? [],
            source: .link
        )

        if let startTime = draft.startTime, !startTime.isEmpty {
            guard let parsedStartTime = parseTime(startTime, on: date) else {
                throw ShowLinkParsingError.invalidResponse
            }
            showDraft.startTime = parsedStartTime
        } else {
            showDraft.startTime = nil
        }
        if let endDate = draft.endDate, !endDate.isEmpty {
            guard let parsedEndDate = parseDate(endDate) else {
                throw ShowLinkParsingError.invalidResponse
            }
            showDraft.endDate = parsedEndDate
        }
        if let endTime = draft.endTime, !endTime.isEmpty {
            guard let parsedEndTime = parseTime(endTime, on: showDraft.endDate ?? date) else {
                throw ShowLinkParsingError.invalidResponse
            }
            showDraft.endTime = parsedEndTime
        }

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
        if !showDraft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedFields.insert(.artist)
        }
        showDraft.recognizedFields = recognizedFields

        return showDraft
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
    let endDate: String?
    let endTime: String?
    let venueName: String
    let venueAddr: String
    let artist: String
    let coverImageURL: String?
    let artistAvatarURLs: [String]?
    let priceRange: String
    let source: String
}
