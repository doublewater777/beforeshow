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
        ("axs.com", "AXS")
    ]

    static let supportSummary = "大麦、秀动、猫眼、票星球、纷玩岛、Ticketmaster、DICE、AXS"

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
            showDraft.startTime = parseTime(startTime, on: date)
        } else {
            showDraft.startTime = nil
        }
        if let endDate = draft.endDate, !endDate.isEmpty {
            showDraft.endDate = parseDate(endDate)
        }
        if let endTime = draft.endTime, !endTime.isEmpty {
            showDraft.endTime = parseTime(endTime, on: showDraft.endDate ?? date)
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
        return DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ).date
    }

    private func parseTime(_ string: String, on date: Date) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
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
