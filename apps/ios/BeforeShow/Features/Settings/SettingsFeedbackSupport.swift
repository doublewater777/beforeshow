import Foundation

struct FeedbackDiagnostics: Equatable {
    let appVersion: String
    let osVersion: String
}

struct FeedbackDraft: Equatable {
    var message: String
}

struct FeedbackPayload: Equatable {
    let message: String
    let diagnostics: FeedbackDiagnostics
}

enum FeedbackValidationError: Error, Equatable {
    case emptyMessage
    case messageTooLong
}

struct FeedbackPayloadBuilder {
    static let maximumMessageLength = 2_000

    var diagnosticsProvider: () -> FeedbackDiagnostics

    init(diagnosticsProvider: @escaping () -> FeedbackDiagnostics = {
        FeedbackDiagnostics(
            appVersion: AppVersionInformation.current.marketingVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }) {
        self.diagnosticsProvider = diagnosticsProvider
    }

    init(appVersion: AppVersionInformation, osVersion: String) {
        self.init {
            FeedbackDiagnostics(appVersion: appVersion.marketingVersion, osVersion: osVersion)
        }
    }

    static func messageLength(_ message: String) -> Int {
        message.unicodeScalars.count
    }

    func build(from draft: FeedbackDraft) throws -> FeedbackPayload {
        let trimmedMessage = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw FeedbackValidationError.emptyMessage
        }
        guard Self.messageLength(draft.message) <= Self.maximumMessageLength else {
            throw FeedbackValidationError.messageTooLong
        }

        return FeedbackPayload(
            message: trimmedMessage,
            diagnostics: diagnosticsProvider()
        )
    }
}

enum FeedbackSubmissionError: Error, Equatable {
    case networkFailure
    case messageTooLong
    case rateLimited
    case rejected
}

struct RemoteFeedbackSubmissionService {
    var client: BeforeShowCloudClient

    func submit(_ payload: FeedbackPayload) async throws {
        let data: Data
        do {
            data = try await client.postJSON(
                path: "submitFeedback",
                body: RequestBody(
                    appInstanceId: client.credentials.appInstanceId,
                    appSignature: client.credentials.appSignature,
                    message: payload.message,
                    appVersion: payload.diagnostics.appVersion,
                    osVersion: payload.diagnostics.osVersion
                )
            )
        } catch {
            throw FeedbackSubmissionError.networkFailure
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw FeedbackSubmissionError.rejected
        }
        guard response.ok else {
            switch response.error?.code {
            case "MESSAGE_TOO_LONG":
                throw FeedbackSubmissionError.messageTooLong
            case "RATE_LIMITED":
                throw FeedbackSubmissionError.rateLimited
            default:
                throw FeedbackSubmissionError.rejected
            }
        }
    }

    private struct RequestBody: Encodable {
        let appInstanceId: String
        let appSignature: String
        let message: String
        let appVersion: String
        let osVersion: String
    }

    private struct Response: Decodable {
        let ok: Bool
        let error: BackendError?
    }

    private struct BackendError: Decodable {
        let code: String
    }
}
