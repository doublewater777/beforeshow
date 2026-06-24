import Foundation
import SwiftData

enum RoundTripDirection: String, CaseIterable, Codable, Equatable {
    case outbound
    case `return`

    var displayName: String {
        switch self {
        case .outbound: return "去程"
        case .return: return "返程"
        }
    }
}

enum ReturnPlanState: String, CaseIterable, Codable, Equatable {
    case undecided
    case planned
}

enum RoundTripDraftError: Error, Equatable {
    case insufficientDirectionInformation
    case missingReliableEvidence
    case invalidGenerationPayload
    case networkFailure
    case backendRejected(String)
}

struct RoundTripEvidence: Codable, Equatable {
    let title: String
    let url: URL?

    init(title: String, url: URL? = nil) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
    }
}

struct RoundTripDraftStep: Codable, Equatable {
    let title: String
    let detail: String
}

struct RoundTripDraft: Equatable {
    let direction: RoundTripDirection
    let summary: String
    let steps: [RoundTripDraftStep]
    let evidence: [RoundTripEvidence]
}

extension RoundTripDraft: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case direction
        case summary
        case steps
        case evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try StrictGenerationDecoding.rejectExtraKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.stringValue))
        )

        let type = try container.decode(String.self, forKey: .type)
        guard type == "roundTripDraft" else {
            throw RoundTripDraftError.invalidGenerationPayload
        }

        let direction = try container.decode(RoundTripDirection.self, forKey: .direction)
        let summary = try container.decode(String.self, forKey: .summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = try container.decode([RoundTripDraftStep].self, forKey: .steps)
        let evidence = try container.decode([RoundTripEvidence].self, forKey: .evidence)

        guard !summary.isEmpty, !steps.isEmpty, !evidence.isEmpty else {
            throw RoundTripDraftError.invalidGenerationPayload
        }

        self.init(direction: direction, summary: summary, steps: steps, evidence: evidence)
    }
}

extension RoundTripDraft {
    var editableText: String {
        let stepText = steps.map { "\($0.title)：\($0.detail)" }.joined(separator: "\n")
        let evidenceText = evidence.map { item in
            if let url = item.url {
                return "依据：\(item.title) \(url.absoluteString)"
            }
            return "依据：\(item.title)"
        }.joined(separator: "\n")

        return [summary, stepText, evidenceText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

struct RoundTripDraftRequest: Equatable {
    let show: Show
    let direction: RoundTripDirection
    let origin: String?
    let destination: String?
    let hotel: String?
    let meetingPoint: String?
    let notes: String?

    var hasEnoughDirectionInformation: Bool {
        switch direction {
        case .outbound:
            return hasText(origin) || hasText(meetingPoint)
        case .return:
            return hasText(destination) || hasText(hotel) || hasText(meetingPoint) || hasText(notes)
        }
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct RoundTripDraftBuilder {
    func makeDraft(
        for request: RoundTripDraftRequest,
        evidence: [RoundTripEvidence],
        proposedSummary: String,
        proposedSteps: [RoundTripDraftStep]
    ) throws -> RoundTripDraft {
        guard request.hasEnoughDirectionInformation else {
            throw RoundTripDraftError.insufficientDirectionInformation
        }

        let reliableEvidence = evidence.filter { !$0.title.isEmpty }
        guard !reliableEvidence.isEmpty else {
            throw RoundTripDraftError.missingReliableEvidence
        }

        return RoundTripDraft(
            direction: request.direction,
            summary: proposedSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: proposedSteps,
            evidence: reliableEvidence
        )
    }
}

@Model
final class RoundTripPlan {
    var id: UUID
    var showID: UUID
    var outboundContent: String?
    var returnContent: String?
    var returnNote: String?
    var createdAt: Date
    var updatedAt: Date

    private var returnStateRawValue: String

    var returnState: ReturnPlanState {
        get { ReturnPlanState(rawValue: returnStateRawValue) ?? .undecided }
        set {
            returnStateRawValue = newValue.rawValue
            touch()
        }
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        outboundContent: String? = nil,
        returnContent: String? = nil,
        returnState: ReturnPlanState = .undecided,
        returnNote: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.outboundContent = trimmedOptional(outboundContent)
        self.returnContent = trimmedOptional(returnContent)
        self.returnStateRawValue = returnState.rawValue
        self.returnNote = trimmedOptional(returnNote)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func saveOutbound(_ content: String) {
        outboundContent = trimmedOptional(content)
        touch()
    }

    func saveReturn(_ content: String) {
        returnContent = trimmedOptional(content)
        returnState = .planned
        touch()
    }

    func markReturnUndecided(note: String? = nil) {
        returnContent = nil
        returnNote = trimmedOptional(note)
        returnState = .undecided
        touch()
    }

    func applySavedUserEdit(_ content: String, direction: RoundTripDirection) {
        switch direction {
        case .outbound:
            saveOutbound(content)
        case .return:
            saveReturn(content)
        }
    }

    private func touch() {
        updatedAt = Date()
    }
}

@MainActor
protocol RoundTripDraftGenerating: Sendable {
    func generate(for request: RoundTripDraftRequest) async throws -> RoundTripDraft
}

struct RemoteRoundTripDraftGenerationService: RoundTripDraftGenerating {
    var baseURL: URL
    var appInstanceId: String
    var appSignature: String
    var session: URLSessionProtocol

    init(
        baseURL: URL,
        appInstanceId: String,
        appSignature: String,
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.appInstanceId = appInstanceId
        self.appSignature = appSignature
        self.session = session
    }

    func generate(for request: RoundTripDraftRequest) async throws -> RoundTripDraft {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(RequestBody(
            appInstanceId: appInstanceId,
            appSignature: appSignature,
            type: "roundTripDraft",
            requestId: UUID().uuidString,
            locale: "zh-CN",
            show: ShowPayload(show: request.show),
            direction: request.direction.rawValue,
            userPlaces: UserPlaces(
                origin: trimmedOptional(request.origin),
                destination: trimmedOptional(request.destination),
                hotel: trimmedOptional(request.hotel),
                meetingPoint: trimmedOptional(request.meetingPoint)
            ),
            constraints: Constraints(
                arrivalBy: request.direction == .outbound ? DateFormatter.generationDay.string(from: request.show.effectiveDate) : nil,
                departAfter: request.direction == .return ? DateFormatter.generationDay.string(from: request.show.effectiveDate) : nil,
                notes: trimmedOptional(request.notes)
            )
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RoundTripDraftError.networkFailure
        }

        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: data)
        guard decoded.ok else {
            throw RoundTripDraftError.backendRejected(decoded.error?.message ?? "生成失败")
        }

        guard let draft = decoded.response else {
            throw RoundTripDraftError.invalidGenerationPayload
        }

        return draft
    }

    private func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct RequestBody: Encodable {
        let appInstanceId: String
        let appSignature: String
        let type: String
        let requestId: String
        let locale: String
        let show: ShowPayload
        let direction: String
        let userPlaces: UserPlaces
        let constraints: Constraints
    }

    private struct ShowPayload: Encodable {
        let name: String
        let date: String
        let city: String?
        let venueName: String?
        let type: String
        let artists: [String]?

        init(show: Show) {
            self.name = show.name
            self.date = DateFormatter.generationDay.string(from: show.effectiveDate)
            self.city = show.city
            self.venueName = show.venueName
            self.type = show.type.rawValue
            self.artists = show.artist.map { [$0] }
        }
    }

    private struct UserPlaces: Encodable {
        let origin: String?
        let destination: String?
        let hotel: String?
        let meetingPoint: String?
    }

    private struct Constraints: Encodable {
        let arrivalBy: String?
        let departAfter: String?
        let notes: String?
    }

    private struct GenerationResponse: Decodable {
        let ok: Bool
        let response: RoundTripDraft?
        let error: ErrorInfo?
    }

    private struct ErrorInfo: Decodable {
        let code: String?
        let message: String
    }
}

private func trimmedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private enum StrictGenerationDecoding {
    struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    static func rejectExtraKeys(in decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let unknownKeys = container.allKeys
            .map(\.stringValue)
            .filter { !allowed.contains($0) }

        if !unknownKeys.isEmpty {
            throw RoundTripDraftError.invalidGenerationPayload
        }
    }
}

private extension DateFormatter {
    static let generationDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
